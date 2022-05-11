/*
    C-readline.c - readline and history bindings for Lua

   This Lua5 module is Copyright (c) 2013, Peter J Billam
                     www.pjb.com.au

 This module is free software; you can redistribute it and/or
       modify it under the same terms as Lua5 itself.
*/

#include <lua.h>
#include <lauxlib.h>
/* #include <string.h>  strlen() & friends, including strerror */
/* #include <unistd.h>  isatty() */

/* --------------- from man readline -------------------- */
#include <stdio.h>
#include <stdlib.h>
/* #include <strings.h>  2.8 20210106 strerror is not in string.h ? */
#include <string.h>
#include <readline/readline.h>
#include <readline/history.h>
/* http://cnswww.cns.cwru.edu/php/chet/readline/rltop.html
   http://cnswww.cns.cwru.edu/php/chet/readline/readline.html#SEC52
     (totally alarming :-( )
   http://cnswww.cns.cwru.edu/php/chet/readline/history.html#IDX5
     (only moderately alarming)
   http://cnswww.cns.cwru.edu/php/chet/readline/readline.html#IDX207
   Variable: FILE * rl_instream
     The stdio stream from which Readline reads input.
     If NULL, Readline defaults to stdin. 
   Variable: FILE * rl_outstream
     The stdio stream to which Readline performs output.
     If NULL, Readline defaults to stdout. 
	http://man7.org/linux/man-pages/man3/ctermid.3.html
	http://man7.org/linux/man-pages/man3/fopen.3.html
	http://man7.org/linux/man-pages/man3/fileno.3.html
	http://man7.org/linux/man-pages/man3/isatty.3.html
*/
/* see Programming in Lua p.233 */
/* apparently a BUG: after being invoked, c_readline leaves SIGWINCH
   handling messed up, and the kernel unable to follow further changes
   in size; thence also tput, stty size, resize, $COLS $ROWS, etc...
   Only  xwininfo -id $WINDOWID  seems to get up-to-date data.
   Surprisingly, rl_catch_sigwinch and rl_cleanup_after_signal have no effect
   http://cnswww.cns.cwru.edu/php/chet/readline/readline.html#SEC43
*/

static int c_readline(lua_State *L) {  /* prompt in, line out */
	size_t len;
	const char *prompt = lua_tolstring(L, 1, &len);
	char buffer[L_ctermid];
	const char *devtty = ctermid(buffer);   /* 20130919 1.1 */
	FILE *tty_stream;
	if (devtty != NULL) {
		tty_stream  = fopen(devtty, "a+");
		if (tty_stream != NULL) {
			/* int tty_fd = fileno(tty_stream); */
			rl_instream  = tty_stream;
			rl_outstream = tty_stream;
		}
	}
	/* rl_catch_sigwinch = 0; rl_set_signals();  no effect :-( 1.3 */
    const char *line   = readline(prompt);
	/* rl_cleanup_after_signal(); rl_clear_signals();  no effect :-( 1.3 */
	lua_pushstring(L, line);
	if (tty_stream != NULL) { fclose(tty_stream); }
	return 1;
}

static int c_tabcompletion(lua_State *L) {  /* Lua stack: is_on */
	int is_on = lua_toboolean(L, 1);
    if (is_on) {
		rl_bind_key ('\t', rl_complete);
	} else {
		rl_bind_key ('\t', rl_insert);
	}
	return 0;
}

static int c_history_length(lua_State *L) {  /* void in, length out */
    lua_Integer n = history_length;
	lua_pushinteger(L, n);
	return 1;
}

static int c_using_history(lua_State *L) {  /* void in, void out */
    using_history();
	return 0;
}

static int c_clear_history(lua_State *L) {  /* void in, void out */
    clear_history();
	return 0;
}

static int c_add_history(lua_State *L) {  /* Lua stack: str to be added */
	size_t len;
	const char *str  = lua_tolstring(L, 1, &len);
    add_history(str);
	return 0;
}

static int c_append_history(lua_State *L) {  /* num,filename in, rc out */
	lua_Integer num = lua_tointeger(L, 1);
	size_t len;
	const char *filename = lua_tolstring(L, 2, &len);
    lua_Integer rc = append_history(num, filename);
	lua_pushinteger(L, rc);
	return 1;
}

static int c_read_history(lua_State *L) {  /* filename in, returncode out */
	size_t len;
	const char *filename  = lua_tolstring(L, 1, &len);
    lua_Integer rc = read_history(filename);
	lua_pushinteger(L, rc);
	return 1;
	/* so maybe we should provide access to char *strerror(int errnum); */
}

static int c_strerror(lua_State *L) {  /* errnum in, errstr out */
	lua_Integer errnum = lua_tointeger(L, 1);
	const char * str = strerror(errnum);
	lua_pushstring(L, str);
	return 1;
}

static int c_stifle_history(lua_State *L) {  /* Lua stack: num */
	lua_Integer num  = lua_tointeger(L, 1);
    stifle_history(num);
	return 0;
}

static int c_write_history(lua_State *L) {  /* filename in, returncode out */
	size_t len;
	const char *filename  = lua_tolstring(L, 1, &len);
    lua_Integer rc = write_history(filename);
	lua_pushinteger(L, rc);
	return 1;
}

static int c_history_truncate_file(lua_State *L) { /* filename,num in rc out */
	size_t len;
	const char *filename  = lua_tolstring(L, 1, &len);
	lua_Integer num       = lua_tointeger(L, 2);
    lua_Integer rc = history_truncate_file(filename, num);
	lua_pushinteger(L, rc);
	return 1;
}

/* ------------------ alternate interface ---------------------- */

/*
 * saves the last given callback handler and its Lua state
 * 
 * ouch: this is not reentrant!
 */
static int alternate_interface_callback = LUA_NOREF;
static lua_State *last_state = NULL;
static FILE *callback_tty_stream; /* <-- new */

/*
 * calls the registered callback handler with `line`
 */
static void handler_calls_lua_callback (char *line) {
    lua_rawgeti(last_state, LUA_REGISTRYINDEX, alternate_interface_callback);
    lua_pushstring(last_state, line);
    lua_call(last_state, 1, 0);
}

static int c_callback_handler_install(lua_State *L) {
	char buffer[L_ctermid];
    const char *prompt;
	/* copied from c_readline */
	const char *devtty = ctermid(buffer);   /* 20130919 1.1 */
	if (devtty != NULL) {
		callback_tty_stream  = fopen(devtty, "a+");
		if (callback_tty_stream != NULL) {
			rl_instream  = callback_tty_stream;
			rl_outstream = callback_tty_stream;
		}
	}
	prompt = luaL_checkstring(L, 1);
    luaL_checktype(L, 2, LUA_TFUNCTION);
    luaL_unref(L, LUA_REGISTRYINDEX, alternate_interface_callback);
    alternate_interface_callback = luaL_ref(L, LUA_REGISTRYINDEX);
    rl_callback_handler_install(prompt, handler_calls_lua_callback);
    last_state = L;
    return 0;
}

static int c_callback_read_char(lua_State *L) {
    rl_callback_read_char();
    return 0;
}

#ifdef RL_VERSION_MAJOR
#if RL_VERSION_MAJOR >= 7
static int c_callback_sigcleanup(lua_State *L) {
    rl_callback_sigcleanup();
    return 0;
}
#endif
#endif

static int c_callback_handler_remove(lua_State *L) {
	if (callback_tty_stream != NULL) { fclose(callback_tty_stream); } /* new */
    rl_callback_handler_remove();
    return 0;
}

/* --------------- interface to custom completion ------------- */

/*
 * this isn't reentrant either — and reuses last_state
 */

static int complete_callback = LUA_NOREF;
static char **completions = NULL;

char *dummy_generator(const char *text, int state) {
    return completions[state];
}

static char **handler_calls_completion_callback(const char *text, int start, int end) {
    size_t i;  /* ? int ? */
    size_t number_of_completions;

    rl_attempted_completion_over = 1;
	lua_settop(last_state, 0);   /* 2.1 */
    lua_rawgeti(last_state, LUA_REGISTRYINDEX, complete_callback);
    lua_pushstring(last_state, rl_line_buffer);
    lua_pushinteger(last_state, (lua_Integer) start+1);
    lua_pushinteger(last_state, (lua_Integer) end+1);
    lua_call(last_state, 3, 1);
    luaL_checktype(last_state, 1, LUA_TTABLE);
	/* lua_rawlen is not available in lua5.1. Use lua_objlen instead */
	/* http://www.lua.org/manual/5.1/manual.html#lua_objlen */
#if LUA_VERSION_NUM >= 502
    number_of_completions = lua_rawlen(last_state, 1);
#else
    number_of_completions = lua_objlen(last_state, 1);
#endif
    if (!number_of_completions) return NULL;

    /* malloc never fails due to overcommit */
    completions = malloc(sizeof(char *)*(1+number_of_completions));

    for (i = 0; i < number_of_completions; i++) {
        size_t length;
        const char *tmp;
        lua_rawgeti(last_state, 1, i+1);
        tmp = luaL_checkstring(last_state, 2);
#if LUA_VERSION_NUM >= 502
        length = 1 + lua_rawlen(last_state, 2);
#else
        length = 1 + lua_objlen(last_state, 2);
#endif
        completions[i] = malloc(sizeof(char)*length);
        strncpy(completions[i], tmp, length);
        lua_remove(last_state, 2);
    }

    /* sentinel NULL means: end of list */
    completions[number_of_completions] = NULL;

    return rl_completion_matches(text, dummy_generator);
}

static int c_set_readline_name(lua_State *L) {
    luaL_checktype(L, 1, LUA_TSTRING);
    rl_readline_name = (const char *) lua_tolstring(L, 1, NULL);  /* 2.8 */
    return 0;
}

static int c_set_complete_function(lua_State *L) {
    luaL_checktype(L, 1, LUA_TFUNCTION);
    luaL_unref(L, LUA_REGISTRYINDEX, complete_callback);
    complete_callback = luaL_ref(L, LUA_REGISTRYINDEX);
    rl_attempted_completion_function = handler_calls_completion_callback;
    last_state = L;
    return 0;
}

static int c_set_default_completer(lua_State *L) {
    rl_attempted_completion_function = NULL;
    return 0;
}

static int c_set_completion_append_character(lua_State *L) {   /* 2.2 */
	size_t len;
	const char *s = lua_tolstring(L, -1, &len);  /* PiL4 p.280 */
	rl_completion_append_character = s[0];
    return 0;
}

/* ----------------- evolved from C-midialsa.c ---------------- */
struct constant {  /* Gems p. 334 */
    const char * name;
    int value;
};
static const struct constant constants[] = {
    /* {"Version", Version}, */
    {NULL, 0}
};

static const luaL_Reg prv[] = {  /* private functions */
    {"add_history",           c_add_history},
    {"append_history",        c_append_history},
    {"clear_history",         c_clear_history},
    {"history_length",        c_history_length},
    {"history_truncate_file", c_history_truncate_file},
    {"read_history",          c_read_history},
    {"readline",              c_readline},
    {"stifle_history",        c_stifle_history},
    {"strerror",              c_strerror},
    {"tabcompletion",         c_tabcompletion},
    {"using_history",         c_using_history},
    {"callback_handler_install", c_callback_handler_install},
    {"callback_read_char",    c_callback_read_char},
#ifdef RL_VERSION_MAJOR
#if RL_VERSION_MAJOR >= 7
    {"callback_sigcleanup",   c_callback_sigcleanup},
#endif
#endif
    {"callback_handler_remove", c_callback_handler_remove},
    {"set_readline_name", c_set_readline_name},
    {"set_complete_function", c_set_complete_function},
    {"set_default_complete_function", c_set_default_completer},
    {"set_completion_append_character", c_set_completion_append_character},
    {NULL, NULL}
};

static int initialise(lua_State *L) {  /* Lua Programming Gems p. 335 */
    /* Lua stack: aux table, prv table, dat table */
    int index;  /* define constants in module namespace */
    for (index = 0; constants[index].name != NULL; ++index) {
        lua_pushinteger(L, constants[index].value);
        lua_setfield(L, 3, constants[index].name);
    }
    /* lua_pushvalue(L, 1);   * set the aux table as environment */
    /* lua_replace(L, LUA_ENVIRONINDEX);
       unnecessary here, fortunately, because it fails in 5.2 */
    lua_pushvalue(L, 2); /* register the private functions */
#if LUA_VERSION_NUM >= 502
    luaL_setfuncs(L, prv, 0);    /* 5.2 */
    return 0;
#else
    luaL_register(L, NULL, prv); /* 5.1 */
    return 0;
#endif
}

int luaopen_readline(lua_State *L) {
    lua_pushcfunction(L, initialise);
    return 1;
}

