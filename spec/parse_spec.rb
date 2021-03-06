require 'rubygems'
require 'rspec'
require 'rspec/expectations'
require 'treetop'
require File.join(File.dirname(__FILE__), "../lib/apacheconf_parser")


describe ApacheconfParser do
  context "general parser machinery" do
    before(:each) do
      @file_content = %{
        <VirtualHost 10.10.10.1:443>
          ServerName test.co.za
          ServerAlias www.test.co.za
          DocumentRoot /usr/www/users/test
          <Directory /usr/www/users/test>
            Options blah blah
          </Directory>
        <VirtualHost>
      }
    
      @fh = mock("File", :null_object => true)
      File.should_receive(:new).with("/etc/apache/httpd.conf").and_return(@fh)
      @fh.should_receive(:close).and_return(nil)
    end

    it "should open httpd.conf in its default location on debian servers" do
      @fh.should_receive(:read).and_return(@file_content)
      parser = ApacheconfParser.new
    end
  
    it "should read the content of the httpd.conf file into memory" do
      @fh.should_receive(:read).and_return(@file_content)
      parser = ApacheconfParser.new
      parser.file_content.should == @file_content
    end
  
    it "should parse a directive into a hash" do
      @file_content = "Options Indexes Includes FollowSymLinks ExecCGI"
      @fh.should_receive(:read).and_return(@file_content)
      parser = ApacheconfParser.new
      parser.ast.should == [{:Options => ['Indexes', 'Includes', 'FollowSymLinks', 'ExecCGI'] }]
    end
  
    it "should parse a directory entry into a hash" do
      @file_content = "<Directory /usr/www/users/blah>
        Options Indexes Includes FollowSymLinks ExecCGI
      </Directory>"
      @fh.should_receive(:read).and_return(@file_content)
      parser = ApacheconfParser.new
      parser.ast.should == 
      [{:directory=>"/usr/www/users/blah", 
        :entries=>
        [ 
          {:Options=>["Indexes", "Includes", "FollowSymLinks", "ExecCGI"]}
        ]
       }
      ]
    end
  
    it "should allow the port specification in a virtualhost header to be optional" do
      file_content = "<VirtualHost 10.11.12.13>
      </VirtualHost>"
      @fh.should_receive(:read).and_return(file_content)
      parser = ApacheconfParser.new
      parser.ast.should == [{ :ip_addr=>[10, 11, 12, 13], :entries=>[]}]
    end

    it "should ignore comments" do
      file_content = "# this is a comment"
      @fh.should_receive(:read).and_return(file_content)
      parser = ApacheconfParser.new
      parser.ast.should == []
    end

    it "should parse a vhost entry into a hash" do
      file_content = "
      ServerName blah.co.za
      Options some options
      ####
      # lets add a comment here
      <VirtualHost 10.10.10.2:123>
        ServerName www.test123.co.za
        ServerAlias www1.test123.co.za
        ServerAlias www2.test123.co.za
        DocumentRoot /usr/www/users/blah
        <Directory /usr/www/users/blah>
          # and another comment goes here   
          Options Indexes Includes FollowSymLinks ExecCGI
        </Directory>
      </VirtualHost>"
      @fh.should_receive(:read).and_return(file_content)
      parser = ApacheconfParser.new
      parser.ast.should == 
      [
        {:ServerName=>["blah.co.za"]}, 
        {:Options=>["some", "options"]}, 
        {:port=>123, :ip_addr=>[10, 10, 10, 2], :entries=>
          [
            {:ServerName=>["www.test123.co.za"]}, 
            {:ServerAlias=>["www1.test123.co.za"]}, 
            {:ServerAlias=>["www2.test123.co.za"]}, 
            {:DocumentRoot=>["/usr/www/users/blah"]}, 
            {:directory=>"/usr/www/users/blah", :entries=>
              [
                {:Options=>["Indexes", "Includes", "FollowSymLinks", "ExecCGI"]}
              ]
            }
          ]
        }
      ]
    end
    
    it "should parse a multiline directive broken up with '\\' characters" do
      file_content = %{
        SetEnvIf User-Agent ".*MSIE.*" \
        nokeepalive ssl-unclean-shutdown \
          downgrade-1.0 force-response-1.0
      }
      @fh.should_receive(:read).and_return(file_content)
      parser = ApacheconfParser.new
      parser.ast.should == 
      [
        {:SetEnvIf=>
          ["User-Agent", "\".*MSIE.*\"", "nokeepalive", "ssl-unclean-shutdown", "downgrade-1.0", "force-response-1.0"]
        }
      ]
    end
    
    it "should parse the common SSL directives" do
      file_content = %{
           # hos_config
              SSLEngine on
      	SSLCACertificateFile /etc/apache/ssl.crt/ourca.crt
              SSLCertificateFile /etc/apache/ssl.crt/ourcrtfile.crt
              SSLCertificateKeyFile /etc/apache/ssl.key/ourkeyfile.key
              SSLOptions +FakeBasicAuth +ExportCertData +CompatEnvVars +StrictRequire
              SSLLogLevel warn
              SSLVerifyClient 0
              SSLVerifyDepth 1
              SetEnvIf User-Agent ".*MSIE.*" \
              nokeepalive ssl-unclean-shutdown \
                downgrade-1.0 force-response-1.0
              SSLProtocol all
              SSLCipherSuite ALL:!ADH:!EXPORT56:RC4+RSA:+HIGH:+MEDIUM:+LOW:+SSLv2:+EX
      }
      @fh.should_receive(:read).and_return(file_content)
      parser = ApacheconfParser.new
      parser.ast.should == 
      [
        {:SSLEngine=>["on"]}, 
        {:SSLCACertificateFile=>["/etc/apache/ssl.crt/ourca.crt"]}, 
        {:SSLCertificateFile=>["/etc/apache/ssl.crt/ourcrtfile.crt"]}, 
        {:SSLCertificateKeyFile=>["/etc/apache/ssl.key/ourkeyfile.key"]}, 
        {:SSLOptions=>["+FakeBasicAuth", "+ExportCertData", "+CompatEnvVars", "+StrictRequire"]}, 
        {:SSLLogLevel=>["warn"]}, 
        {:SSLVerifyClient=>["0"]}, 
        {:SSLVerifyDepth=>["1"]}, 
        {:SetEnvIf=>["User-Agent", "\".*MSIE.*\"", "nokeepalive", "ssl-unclean-shutdown", "downgrade-1.0", "force-response-1.0"]}, 
        {:SSLProtocol=>["all"]}, 
        {:SSLCipherSuite=>["ALL:!ADH:!EXPORT56:RC4+RSA:+HIGH:+MEDIUM:+LOW:+SSLv2:+EX"]}
      ]
    end
  end
  
  context "when set to work on an actual httpd.conf file" do
    it "should parse an entire httpd.conf file" do
      path = 'spec/httpd.conf'
      parser = ApacheconfParser.new(path)
      parser.ast.should_not == nil
    end
  
  end
    
end
