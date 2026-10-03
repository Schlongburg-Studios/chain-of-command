"""Run the Lua test suite without a Lua install, using lupa's bundled Lua 5.4.

    pip install lupa
    python tests/run.py [-v] [suite-filter]
"""
import os
import sys

try:
    from lupa import lua54
except ImportError:
    sys.exit('lupa is not installed. Run: pip install lupa   (or use: lua tests/run.lua)')

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__))).replace('\\', '/')
lua = lua54.LuaRuntime()
lua_arg = lua.table_from({i + 1: a for i, a in enumerate(sys.argv[1:])})
lua_arg[0] = root + '/tests/run.lua'
lua.globals().arg = lua_arg
lua.execute('dofile(arg[0])')
