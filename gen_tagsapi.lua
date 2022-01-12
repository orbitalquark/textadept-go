#!/usr/bin/lua
-- Copyright 2022 Mitchell. See LICENSE.
-- Generates tags and api documentation for Go's standard library with the help of `go doc`
-- and `gotags`.

-- LuaFormatter off
local std = {
  --'archive',
  --'archive/tar',
  --'archive/zip',
  'bufio',
  'builtin',
  'bytes',
  --'compress',
  --'compress/bzip2',
  --'compress/flate',
  --'compress/gzip',
  --'compress/lzw',
  --'compress/zlib',
  --'container',
  --'container/heap',
  --'container/list',
  --'container/ring',
  --'context',
  --'crypto',
  --'crypto/aes',
  --'crypto/cipher',
  --'crypto/des',
  --'crypto/dsa',
  --'crypto/ecdsa',
  --'crypto/ed25519',
  --'crypto/elliptic',
  --'crypto/hmac',
  --'crypto/md5',
  --'crypto/rand',
  --'crypto/rc4',
  --'crypto/rsa',
  --'crypto/sha1',
  --'crypto/sha256',
  --'crypto/sha512',
  --'crypto/subtle',
  --'crypto/tls',
  --'crypto/x509',
  --'crypto/x509/pkix',
  --'database',
  --'database/sql',
  --'database/sql/driver',
  --'debug',
  --'debug/dwarf',
  --'debug/elf',
  --'debug/gosym',
  --'debug/macho',
  --'debug/pe',
  --'debug/plan9obj',
  'embed',
  'encoding',
  --'encoding/ascii85',
  --'encoding/asn1',
  'encoding/base32',
  'encoding/base64',
  'encoding/binary',
  'encoding/csv',
  --'encoding/gob',
  'encoding/hex',
  'encoding/json',
  --'encoding/pem',
  'encoding/xml',
  'errors',
  --'expvar',
  'flag',
  'fmt',
  --'go',
  --'go/ast',
  --'go/build',
  --'go/build/constraint',
  --'go/constant',
  --'go/doc',
  --'go/format',
  --'go/importer',
  --'go/parser',
  --'go/printer',
  --'go/scanner',
  --'go/token',
  --'go/types',
  --'hash',
  --'hash/adler32',
  --'hash/crc32',
  --'hash/crc64',
  --'hash/fnv',
  --'hash/maphash',
  'html',
  'html/template',
  --'image',
  --'image/color',
  --'image/color/palette',
  --'image/draw',
  --'image/gif',
  --'image/jpeg',
  --'image/png',
  --'index',
  --'index/suffixarray',
  'io',
  'io/fs',
  'io/ioutil',
  'log',
  --'log/syslog',
  'math',
  --'math/big',
  --'math/bits',
  'math/cmplx',
  'math/rand',
  --'mime',
  --'mime/multipart',
  --'mime/quotedprintable',
  'net',
  'net/http',
  --'net/http/cgi',
  --'net/http/cookiejar',
  --'net/http/fcgi',
  --'net/http/httptest',
  --'net/http/httptrace',
  --'net/http/httputil',
  --'net/http/pprof',
  --'net/mail',
  --'net/rpc',
  'net/jsonrpc',
  --'net/smtp',
  --'net/textproto',
  'net/url',
  'os',
  'os/exec',
  'os/signal',
  --'os/user',
  'path',
  'path/filepath',
  --'plugin',
  --'reflect',
  'regexp',
  'regexp/syntax',
  'runtime',
  --'runtime/cgo',
  --'runtime/debug',
  --'runtime/metrics',
  --'runtime/pprof',
  --'runtime/race',
  --'runtime/trace',
  'sort',
  'strconv',
  'strings',
  'sync',
  --'sync/atomic',
  --'syscall',
  --'syscall/js',
  'testing',
  'testing/fstest',
  'testing/iotest',
  'testing/quick',
  'text',
  'text/scanner',
  --'text/tabwriter',
  'text/template',
  'text/template/parse',
  'time',
  --'time/tzdata',
  'unicode',
  'unicode/utf16',
  'unicode/utf8',
  --'unsafe',
  --'internal',
  --'internal/abi',
  --'internal/buildcfg',
  --'internal/bytealg',
  --'internal/cfg',
  --'internal/cpu',
  --'internal/execabs',
  --'internal/fmtsort',
  --'internal/goexperiment',
  --'internal/goroot',
  --'internal/goversion',
  --'internal/itoa',
  --'internal/lazyregexp',
  --'internal/lazytemplate',
  --'internal/nettrace',
  --'internal/obscuretestdata',
  --'internal/oserror',
  --'internal/poll',
  --'internal/profile',
  --'internal/race',
  --'internal/reflectlite',
  --'internal/singleflight',
  --'internal/syscall/execenv',
  --'internal/syscall/unix',
  --'internal/syscall/windows',
  --'internal/syscall/windows/registry',
  --'internal/syscall/windows/sysdll',
  --'internal/sysinfo',
  --'internal/testenv',
  --'internal/testlog',
  --'internal/trace',
  --'internal/unsafeheader',
  --'internal/xcoff',
}
-- LuaFormatter on

local apis = {}
local API = '%s %s.%s\\n%s\n'
local API_BUILTIN = '%s %s\\n%s\n'

-- Equivalent to mkdir -p [path].
local function mkdirp(path)
  local dir
  for part in path:gmatch('[^/]+') do
    dir = dir and dir .. '/' .. part or part
    require('lfs').mkdir(dir)
  end
end

-- Returns a fixed up go doc output line such that gotags can parse it.
local function fix_line(line)
  line = line:gsub('%.%.%.$', ''):gsub(', %.%.%.', ''):gsub('{ %.%.%. }', '{}')
  if line:find('^%s*const%s+%S+%s+$') or line:find('^%s*var%s+%S+%s+$') then line = line .. '=0' end
  return line
end

mkdirp('std')
for _, path in ipairs(std) do
  mkdirp('std/' .. path)
  local f = assert(io.open('std/' .. path .. '.go', 'wb'))
  local package_name = path:match('[^/]+$')
  f:write('package ', package_name, '\n')
  local p = io.popen('go doc -short ' .. path)
  for line in p:lines() do
    local kind = line:match('^%s*(%S+)')
    if kind == 'type' and
      (line:match('^%s*%S+%s+%S+%s+struct{') or line:match('^%s*%S+%s+%S+%s+interface{')) then
      -- Of the form:
      -- type Type struct {
      --   ...
      -- }
      --     Documentation.
      --     More documentation.
      --
      -- func Func() *Type
      -- func (t *Type) Method()
      -- ...
      local struct_name = line:match('^%s*%S+%s+(%S+)')
      local p2 = io.popen('go doc -short ' .. path .. '.' .. struct_name)
      local doc_lines, reading_doc_lines = {}, false
      for line2 in p2:lines() do
        if reading_doc_lines and line2:find('^%S') then reading_doc_lines = false end
        if not reading_doc_lines then
          line2 = fix_line(line2)
          f:write(line2, '\n')
          if line2:match('^%S+') == 'func' then
            line2 = line2:gsub('^func%s+', ''):gsub('^%b()%s+', '')
            local name = line2:match('^[%w_]+')
            apis[#apis + 1] = API:format(name, struct_name, line2, '')
          end
          if line2:find('^}') then reading_doc_lines = true end
        else
          doc_lines[#doc_lines + 1] = line2:gsub('^%s+', '')
        end
      end
      p2:close()
      apis[#apis + 1] = API:format(struct_name, package_name, struct_name,
        table.concat(doc_lines, '\\n'))
    else
      line = fix_line(line)
      f:write(line, '\n')
      if kind == 'func' then
        line = line:gsub('^%s*%S+%s+', '')
        local name = line:match('^[%w_]+')
        local p2 = io.popen('go doc -short ' .. path .. '.' .. name)
        local doc_lines = {}
        for line2 in p2:lines() do
          if line2:find('^%s+') then doc_lines[#doc_lines + 1] = line2:gsub('^%s+', '') end
        end
        p2:close()
        if package_name ~= 'builtin' then
          apis[#apis + 1] = API:format(name, package_name, line, table.concat(doc_lines, '\\n'))
        else
          apis[#apis + 1] = API_BUILTIN:format(name, line, table.concat(doc_lines, '\\n'))
        end
      end
    end
  end
  p:close()
  f:close()
end

assert(select(3, os.execute('gotags -f tags -R std')) == 0)
table.sort(apis)
assert(io.open('api', 'wb')):write(table.concat(apis)):close()
