local ffi = require("ffi")
local bit = require("bit")

--  EDIT ME
local testWindows = false
local serverIp = "192.168.0.25" -- Change this to your server's IP address
local serverPort = 8126 -- Change this to your server's port
-- EDIT END

local kernelDllName = "kernelx"

-- Override for local windows testing
if testWindows then
    print("Platform: Windows")
    kernelDllName = "kernel32"
    serverIp = "127.0.0.1"
    cmdExeName = "cmd.exe"
else
    print("Platform: XBOX")
end

--
local kernelx = ffi.load(kernelDllName)

-- Used for file dumping
local fileBuf = membuf.create(0x1000000) -- 16MB

-- Credits to iryont (https://github.com/iryont/lua-struct)
local struct = {}

function struct.pack(format, ...)
  local stream = {}
  local vars = {...}
  local endianness = true

  for i = 1, format:len() do
    local opt = format:sub(i, i)

    if opt == '<' then
      endianness = true
    elseif opt == '>' then
      endianness = false
    elseif opt:find('[bBhHiIlL]') then
      local n = opt:find('[hH]') and 2 or opt:find('[iI]') and 4 or opt:find('[lL]') and 8 or 1
      local val = tonumber(table.remove(vars, 1))

      local bytes = {}
      for j = 1, n do
        table.insert(bytes, string.char(val % (2 ^ 8)))
        val = math.floor(val / (2 ^ 8))
      end

      if not endianness then
        table.insert(stream, string.reverse(table.concat(bytes)))
      else
        table.insert(stream, table.concat(bytes))
      end
    elseif opt:find('[fd]') then
      local val = tonumber(table.remove(vars, 1))
      local sign = 0

      if val < 0 then
        sign = 1
        val = -val
      end

      local mantissa, exponent = math.frexp(val)
      if val == 0 then
        mantissa = 0
        exponent = 0
      else
        mantissa = (mantissa * 2 - 1) * math.ldexp(0.5, (opt == 'd') and 53 or 24)
        exponent = exponent + ((opt == 'd') and 1022 or 126)
      end

      local bytes = {}
      if opt == 'd' then
        val = mantissa
        for i = 1, 6 do
          table.insert(bytes, string.char(math.floor(val) % (2 ^ 8)))
          val = math.floor(val / (2 ^ 8))
        end
      else
        table.insert(bytes, string.char(math.floor(mantissa) % (2 ^ 8)))
        val = math.floor(mantissa / (2 ^ 8))
        table.insert(bytes, string.char(math.floor(val) % (2 ^ 8)))
        val = math.floor(val / (2 ^ 8))
      end

      table.insert(bytes, string.char(math.floor(exponent * ((opt == 'd') and 16 or 128) + val) % (2 ^ 8)))
      val = math.floor((exponent * ((opt == 'd') and 16 or 128) + val) / (2 ^ 8))
      table.insert(bytes, string.char(math.floor(sign * 128 + val) % (2 ^ 8)))
      val = math.floor((sign * 128 + val) / (2 ^ 8))

      if not endianness then
        table.insert(stream, string.reverse(table.concat(bytes)))
      else
        table.insert(stream, table.concat(bytes))
      end
    elseif opt == 's' then
      table.insert(stream, tostring(table.remove(vars, 1)))
      table.insert(stream, string.char(0))
    elseif opt == 'c' then
      local n = format:sub(i + 1):match('%d+')
      local str = tostring(table.remove(vars, 1))
      local len = tonumber(n)
      if len <= 0 then
        len = str:len()
      end
      if len - str:len() > 0 then
        str = str .. string.rep(' ', len - str:len())
      end
      table.insert(stream, str:sub(1, len))
      i = i + n:len()
    end
  end

  return table.concat(stream)
end

ffi.cdef[[
    typedef unsigned char* LPBYTE;
    typedef void* LPVOID;
    typedef unsigned int* LPDWORD;
    typedef char* LPSTR;
    typedef char* LPCSTR;
    typedef wchar_t WCHAR;
    typedef void *HANDLE;
    typedef wchar_t* LPCWSTR;
    typedef wchar_t* LPWSTR;
    typedef unsigned char BOOL;

    typedef struct _FILETIME {
        DWORD dwLowDateTime;
        DWORD dwHighDateTime;
    } FILETIME;

    typedef struct _OVERLAPPED {
        ULONG_PTR Internal;
        ULONG_PTR InternalHigh;
        union {
          struct {
            DWORD Offset;
            DWORD OffsetHigh;
          } DUMMYSTRUCTNAME;
          PVOID Pointer;
        } DUMMYUNIONNAME;
        HANDLE    hEvent;
      } OVERLAPPED, *LPOVERLAPPED;

    typedef struct _SECURITY_ATTRIBUTES {
        DWORD  nLength;
        LPVOID lpSecurityDescriptor;
        BOOL   bInheritHandle;
      } SECURITY_ATTRIBUTES, *PSECURITY_ATTRIBUTES, *LPSECURITY_ATTRIBUTES;

    typedef struct _WIN32_FIND_DATAA {
        DWORD dwFileAttributes;
        FILETIME ftCreationTime;
        FILETIME ftLastAccessTime;
        FILETIME ftLastWriteTime;
        DWORD nFileSizeHigh;
        DWORD nFileSizeLow;
        DWORD dwReserved0;
        DWORD dwReserved1;
        CHAR cFileName[255];
        CHAR cAlternateFilename[14];
        DWORD dwFileType;
        DWORD dwCreatorType;
        WORD wFinderFlag;
    } WIN32_FIND_DATAA;
    
    HANDLE FindFirstFileA(
        LPCSTR lpDirectoryName,
        WIN32_FIND_DATAA *lpFindFileData);
    
    BOOL FindNextFileA(
        HANDLE hFindFile,
        WIN32_FIND_DATAA *lpFindFileData);
    
    BOOL FindClose(HANDLE hFindFile);

    HANDLE CreateFileA(
        LPCSTR                lpFileName,
        DWORD                 dwDesiredAccess,
        DWORD                 dwShareMode,
        LPSECURITY_ATTRIBUTES lpSecurityAttributes,
        DWORD                 dwCreationDisposition,
        DWORD                 dwFlagsAndAttributes,
        HANDLE                hTemplateFile
      );

      BOOL CloseHandle(
        HANDLE hObject
    );

      BOOL ReadFile(
        HANDLE       hFile,
        LPVOID       lpBuffer,
        DWORD        nNumberOfBytesToRead,
        LPDWORD      lpNumberOfBytesRead,
        LPOVERLAPPED lpOverlapped
      );

      DWORD GetLastError();
]]

ffi.cdef[[
    unsigned int XCrdOpenAdapter(HANDLE *hAdapter);
    unsigned int XCrdCloseAdapter(HANDLE hAdapter);
]]

function str(lua_str)
    local len = #lua_str
    local buf = ffi.new("char[?]", len + 1)
    ffi.copy(buf, lua_str, len)
    buf[len] = 0
    return buf
end

function printError(val)
    print("ERROR:" .. val)
end

function logs(sock, val)
  socketSend(sock, str(val .. "\r\n"), #val +2, 0)
end

function bitand(a, b)
    local result = 0
    local bitval = 1
    while a > 0 and b > 0 do
      if a % 2 == 1 and b % 2 == 1 then -- test the rightmost bits
          result = result + bitval      -- set the current bit
      end
      bitval = bitval * 2 -- shift left
      a = math.floor(a/2) -- shift right
      b = math.floor(b/2)
    end
    return result
end

function enumerateUploadDirectory(sock, dirname)
	local finddata = ffi.new("WIN32_FIND_DATAA")
	local findHandle = kernelx.FindFirstFileA(str(dirname .. "\\*"), finddata);
	while(true)
	do
		local fileName = ffi.string(finddata.cFileName)
		local fullName = dirname .. "\\" .. fileName
		print("Uploading " .. fullName)
		local dataStruct = struct.pack("<IIIIII", finddata.dwFileAttributes, finddata.ftLastWriteTime.dwLowDateTime, finddata.ftLastWriteTime.dwHighDateTime, finddata.nFileSizeLow, finddata.nFileSizeHigh, #fullName)
		
		if fileName ~= "." and fileName ~= ".." then
			socketSend(sock, str(dataStruct), #dataStruct, 0)
			socketSend(sock, fullName, #fullName, 0)
		end
		
		if bitand(finddata.dwFileAttributes, 0x10) == 0x10 and fileName ~= "." and fileName ~= ".." then
			enumerateUploadDirectory(sock, fullName)
		elseif fileName ~= "." and fileName ~= ".." then
			local totalFileSize = finddata.nFileSizeLow -- (finddata.nFileSizeHigh * 0x100000000)
			local uploadBytes = 0
			local fileHandle = kernelx.CreateFileA(str(fullName), 0x80000000, 0x7, nil, 3, 0, nil)
			local bytesReadPtr = ffi.new("int[1]")
			print("( " .. totalFileSize .. " bytes)")
			while (uploadBytes < totalFileSize)
			do
				kernelx.ReadFile(fileHandle, fileBuf.buffer, 0x1000000, bytesReadPtr, nil)
				print("read " .. bytesReadPtr[0])
				socketSend(sock, fileBuf.buffer, bytesReadPtr[0], 0)
				uploadBytes = uploadBytes + bytesReadPtr[0]
			end
			kernelx.CloseHandle(fileHandle)
		end
		
		if kernelx.FindNextFileA(findHandle, finddata) == 0 then
			kernelx.CloseHandle(findHandle)
			break
		end
	end
end


print("Opening socket..")
local sock = openTcpConnection(serverIp, serverPort)

enumerateUploadDirectory(sock, "T:")

print("Closing socket...")
closeSocket(sock)
