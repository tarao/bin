#! /usr/bin/env ruby
$:.unshift(File.join(File.dirname($0), 'lib'))
begin
  require 'rubygems'
rescue LoadError
end
require 'getopt'
require 'nkf'

$bin = {
  :ruby  => 'ruby',
  :vim   => 'vim',
  :sh    => 'sh',
  :echo  => 'echo',
  :test  => 'test',
  :which => '/usr/bin/which',
  :cat   => 'cat',
  :bash  => 'bash',
  :zsh   => 'zsh',
  :p7z    => '7z',
}

$archive =
  [
   '7z', 'zip', 'cab', 'arj', 'gz', 'bz2', 'tar', 'cpio', 'rpm', 'deb', 'rar',
  ]

$nkfopt = '-w'
$nkfopt = '-j' if ENV['LANG'] =~ /\.(?:jis|iso[-_]?2022[-_]?jp)/i
$nkfopt = '-e' if ENV['LANG'] =~ /\.euc[-_]?jp/i
$nkfopt = '-s' if ENV['LANG'] =~ /\.s(?:hift)?[-_]?jis/i
$nkfopt = '-w16' if ENV['LANG'] =~ /\.utf[-_]?16/i
$nkfauto = [ 'iso-2022-jp' ]

$nkfrec = '--run-nkf'
$bin[:nkf] = "#{$bin[:ruby]} #{$0} #{$nkfrec}"

$nkfguess = '--run-nkf-guess'
$bin[:nkfguess] = "#{$bin[:ruby]} #{$0} #{$nkfguess}"

$p7zrec = '--run-7z'
$bin[:p7zrec] = "#{$bin[:ruby]} #{$0} #{$p7zrec}"

$vimrec = '--run-vim'

$vimfile = {
  :less   => 'macros/less.vim',
  :escape => 'ansi_escape.vim',
}

#### run nkf

if $*[0] == $nkfrec
  $*.shift
  print(NKF.nkf($nkfopt, ARGF.read))
  exit
end

#### run nkf guess

if $*[0] == $nkfguess
  $*.shift
  print(NKF.guess(ARGF.read))
  exit
end

$fenc = {
  NKF::JIS     => 'iso-2022-jp',
  NKF::EUC     => 'euc-jp',
  NKF::SJIS    => 'sjis',
  NKF::BINARY  => nil,
  NKF::UNKNOWN => nil,
  NKF::ASCII   => 'utf-8',
  NKF::UTF8    => 'utf-8',
  NKF::UTF16   => 'utf-16',
}

### run 7z

if $*[0] == $p7zrec
  $*.shift
  argv = GetOpt.new($*)
  print(`#{$bin[:sh]} -c '</dev/tty #{$bin[:p7z]} e -so #{argv}' 2>/dev/null`)
  exit
end

#### run vim

if $*[0] == $vimrec # close stdin before running vim
  $*.shift
  argv = GetOpt.new($*)
  system("#{$bin[:sh]} -c '</dev/tty #{$bin[:vim]} #{argv}'")
  exit
end

#### do nothing

unless system("#{$bin[:test]} -t 1") # output is not a terminal
  args = $*.map{|v| GetOpt.escape(v)}.join(' ')
  system("#{$bin[:cat]} #{args}")
  exit
end

#### main

def path_exist?(name) # search path
  path = `#{$bin[:which]} #{name}`.strip
  return !path.empty? && system("test -x \"#{path}\"") && path
end

def warn_if(cond, msg)
  return cond && (warn(msg) || true)
end

# vim runtime

$rtpcmd =
  [ "#{$bin[:vim]} -e -s",
    "--cmd 'exe \"silent !#{$bin[:echo]} \" . &runtimepath'",
    "--cmd q",
  ].join(' ')
$rtp = `#{$rtpcmd}`
$rtp = $rtp.strip.split(',')

def rtp_find(runtime)
  return $rtp.map{|v| "#{v}/#{runtime}"}.find{|v| File.exist?(v)}
end

$vinit = <<EOS
let g:ofencs=0
aug vinit
fu VInit(list)
  for x in a:list
    exe 'au vinit BufReadPre <buffer=' . x.i . '> sil if !g:ofencs|let g:ofencs=&fencs|en|se fencs='
    let c='au vinit BufReadPost <buffer=' . x.i . '> sil|sil f ' . x.d . '|filet detect'
    if has_key(x,'f')
      let c.='|sil f' . x.f
    en
    let c.='|exe ''se fencs='' . g:ofencs|au! vinit BufReadPost <buffer=' . x.i . '>'
    exe c
  endfo
endf
EOS

$vfenc = <<EOS
aug vfenc
fu VFEnc(list)
  for x in a:list
    exe 'au vfenc BufReadPost <buffer=' . x.i . '> sil|se ma|setl fenc=' . x.e . '|se noma|au! vfenc BufReadPost <buffer=' . x.i . '>'
  endfo
endf
EOS

# commandline arguments

zsh = path_exist?($bin[:zsh])
bash = path_exist?($bin[:bash])

dargv = { # default values
  :psub   => path_exist?($bin[:zsh]) || path_exist?($bin[:bash]),
  :escape => true,
}
argv = GetOpt.new($*, %w'
  psub
  s|syntax=s
  k|nkf
  x|extract
  e|escape
  v|verbose
  h|help
', dargv)
argv[:shell] = ENV['SHELL'] || argv[:psub]

if argv[:help]
  dargv.each{|k,v| dargv[k] = v ? 'on' : 'off'}
  puts <<"EOM"
Usage: #{File.basename($0)} [-s syntax] [-kevh] [--] file...
Options:
  -s, --syntax   Set syntax.
  -k, --nkf      Use nkf.
  -x, --extract  Extract archive files.
  -e, --escape   Manipulate ANSI escape sequences.
  -v, --verbose  Show extra information (default: #{dargv[:verbose]}).
  -h, --help     Show help.
EOM
  exit
end

# capability
[
 [ argv[:extract] && !path_exist?($bin[:p7z]), $bin[:p7z], :extract ],
 [ argv[:escape] && !rtp_find($vimfile[:escape]), $vimfile[:escape], :escape ],
].each do |b, f, o|
  argv[o] = false if b
  warn_if(b, "'#{f}' not found; --#{o} option switched off")
end

psub = argv[:shell] == bash ? '<(%s)' : '=(%s)'

# exclude non-existing files
files = argv.args + argv.rest
rejected = false
files.reject! do |f|
  r = warn_if(!File.exist?(f), "#{f}: no such file or directory")
  r ||= warn_if(File.directory?(f), "#{f} is a directory")
  rejected ||= r
  r
end

# no input
if files.size < 1 && system("#{$bin[:test]} -t 0")
  msg = "Missing filename (\"#{File.basename($0)} --help\" for help)"
  puts(msg) unless rejected
  exit
end

cmd = []
vimcmd = [ $bin[:vim] ]
vimopt =
  [
   '--cmd',
   'let no_plugin_maps = 1',
   '--cmd',
   "runtime! #{$vimfile[:less]}",
  ] # default options from less.sh

# ANSI escape sequence
vimopt += [ '-c', "runtime #{$vimfile[:escape]}" ] if argv[:escape]

# set syntax explicitly
vimopt += [ '-c', "set syntax=#{argv[:syntax]}" ] if argv[:syntax]

class Object
  def to_vim
    if self.is_a?(String) || self.is_a?(Symbol)
      return "'"+self.to_s+"'"
    elsif self.is_a?(Array)
      return '['+self.map{|x|x.to_vim}.join(',')+']'
    elsif self.is_a?(Hash)
      return '{'+self.keys.map{|k|k.to_vim+':'+self[k].to_vim}.join(',')+'}'
    elsif self.is_a?(TrueClass) || self.is_a?(FalseClass)
      return (self ? 1 : 0).to_s
    else
      return self.to_s
    end
  end
end

if files.length == 0  # read from standard input
  input = argv[:nkf] ? (psub % $bin[:nkf]) : (psub % $bin[:cat])
  vimcmd = [ "#{$bin[:ruby]} #{$0} #{$vimrec}" ] if argv[:psub]
  vimopt += [ '--cmd', 'au BufReadPre * filet off' ]
  vimopt += [ '-c', [ 'sil f [stdin]','redr', 'f',
                      'if !exists("ansi_escape_used")|filet detect|endif',
                    ].join('|')
            ] # rename
  argv[:stdin] = !argv[:psub]
else                  # read from file
  if !argv[:psub] && argv[:nkf]
    input = files.map{|f| GetOpt.escape(f)}.join(' ')
    cmd.unshift("#{$bin[:cat]} #{input}")
    argv[:stdin] = true
  else
    inits=[]
    fencs=[]
    i=0

    files = files.map do |f|
      detect = f
      file = GetOpt.escape(f)
      fenc = nil
      nkf = argv[:nkf]

      translators = []
      extractors = []

      if argv[:extract] && $archive.include?((File.extname(f)||'')[1..-1])
        extractors << $bin[:p7zrec]
        detect = f[0...-(File.extname(f).length)]
      end

      unless nkf === false
        g = extractors + [ $bin[:nkfguess] ]
        fenc = $fenc[`#{[ g[0]+' '+file, *g[1..-1] ].join('|')}`.to_i]
        nkf = true if $nkfauto.include?(fenc) # enable automatically
        nkf = false unless fenc # binary or unknown
      end
      translators << $bin[:nkf] if nkf

      i += 1
      filters = extractors + translators
      if !filters.empty?
        file = "<(#{[ filters[0]+' '+file, *filters[1..-1] ].join('|')})"
      end

      inits << {
        :i => i, :d => detect, :f => detect!=f && f,
      }.delete_if{|k,v| !v} unless filters.empty?
      fencs << { :i => i, :e => fenc } if fenc

      file
    end

    [ :Init, :FEnc, ].each do |x|
      arr = eval(x.to_s.downcase+'s')
      vimopt +=
        [ '--cmd', eval('$v'+x.to_s.downcase).gsub(/^\s+/,''),
          '--cmd', 'call V'+x.to_s+'('+arr.to_vim+')',
        ] unless arr.empty?
    end

    input = files.join(' ')
  end
end

if argv[:stdin]
  input = '-'
  cmd << "#{$bin[:nkf]}" if argv[:nkf]
end

vimcmd += vimopt.map{|v| GetOpt.escape(v)}
vimcmd << input
cmd << vimcmd.join(' ')

if argv[:stdin]
  warn("command: #{cmd.join('|')}") if argv[:verbose]
  system(cmd.join('|'))
else
  warn("command: #{cmd.join('|')}") if argv[:verbose]
  system(argv[:shell], '-c', cmd.join('|'))
end
