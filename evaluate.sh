#! /bin/bash

if [ -n "$1" ]; then pushd $1 ; fi
echo ""

echo "[LuaSkin shared] --> [LuaSkin threaded]:"
ack --objc '\[LuaSkin\s+shared\]'
echo ""

echo "refTable -> [skin refTableFor:USERDATA_TAG]"
ack --objc '[lL]uaRef:\w+'
ack --objc 'luaUnref:\w+'
echo""

echo "Non-unique refTable:"
ack --objc "\w+\s*=\s*\[\w+\s+registerLibrary:"
echo ""

echo "Thread related areas of concern:"
ack --objc 'dispatch_get_main_queue'
ack --objc 'performSelectorOnMainThread:'
echo ""

if [ -n "$1" ]; then popd ; fi
