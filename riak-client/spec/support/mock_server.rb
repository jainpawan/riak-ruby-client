# -*- coding: utf-8 -*-
# Copyright 2010 Sean Cribbs, Sonian Inc., and Basho Technologies, Inc.
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.

# Based on code from Rob Styles and Chris Tierney found at:
#   http://dynamicorange.com/2009/02/18/ruby-mock-web-server/
require 'rack'
require 'openssl'
require 'webrick/https'
require 'rack/handler/webrick'

class MockServer
  attr_accessor :port
  attr_accessor :satisfied

  def initialize(pause = 1)
    self.port = 4000 + rand(61535)
    @block = nil
    @parent_thread = Thread.current
    options = {:AccessLog => [], :Logger => NullLogger.new, :Host => '127.0.0.1'}
    @thread = Thread.new do
      Rack::Handler::WEBrick.run(self, options.merge(:Port => port))
    end
    @ssl_thread = Thread.new do
      Rack::Handler::WEBrick.run(self, options.merge(:Port => port+1,
        :SSLEnable       => true,
        :SSLVerifyClient => OpenSSL::SSL::VERIFY_NONE,
        :SSLCertificate  => read_cert,
        :SSLPrivateKey   => read_pkey,
        :SSLCertName     => [ [ "CN",'127.0.0.1' ] ]))
    end
    sleep pause # give the server time to fire up… YUK!
  end

  def stop
    Thread.kill(@thread)
    Thread.kill(@ssl_thread)
  end

  def expect(status, headers, method, path, query, body)
    attach do |env|
      @satisfied = (env["REQUEST_METHOD"] == method &&
                    env["PATH_INFO"] == path &&
                    env["QUERY_STRING"] == query)
      [status, headers, Array(body)]
    end
  end

  def attach(&block)
    @block = block
  end

  def detach()
    @block = nil
  end

  def call(env)
    begin
      raise "Specify a handler for the request using attach(block), the block should return a valid rack response and can test expectations" unless @block
      @block.call(env)
    rescue Exception => e
      @satisfied = false
      # @parent_thread.raise e
      body = "Bad test code\n#{e.inspect}\n#{e.backtrace}"
      [ 500, { 'Content-Type' => 'text/plain', 'Content-Length' => body.length.to_s }, [ body ]]
    end
  end

  def read_pkey
    OpenSSL::PKey::RSA.new(File.read(File.expand_path(File.dirname(__FILE__) + '/../fixtures/server.cert.key')), 'ripple')
  end

  def read_cert
    OpenSSL::X509::Certificate.new(File.read((File.expand_path(File.dirname(__FILE__) + '/../fixtures/server.cert.crt'))))
  end

  class NullLogger
    def fatal(msg) end
    def error(msg) end
    def warn(msg)  end
    def info(msg)  end
    def debug(msg) end
  end
end
