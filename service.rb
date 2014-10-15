require 'ffi-rzmq'
require 'json'
require 'net/http'

class Service

    attr_accessor :methods

    def initialize(name, options={}, methods={})
        @name = name
        @options = options
        @methods = methods
        puts "Initializing service #{ @name }..."

        @ctx = ZMQ::Context.new
        @socket = @ctx.socket(ZMQ::ROUTER)

        @socket.bind(sprintf('tcp://0.0.0.0:%d', options['bind_port']))
        puts sprintf('tcp://0.0.0.0:%d', options['bind_port'])

        @poller = ZMQ::Poller.new
        @poller.register_readable(@socket)
        @http = Net::HTTP.new('localhost', 8500)

        self.register
        Thread.new { self.pass_checks_loop }
    end

    def listen
        @listener = Thread.new { self.socket_recv_loop }
        @listener.join()
    end

    # Socket receive loop
    # --------------------------------------------------------------------------
    # Each message is a JSON object that should have a 'kind' attribute. If
    # there's a handler function for a given message kind, call it.

    def socket_recv_loop
        while true do
            @poller.poll 10
            @poller.readables.each do |sock|

                # Get client ID and parse message from JSON
                client_id = ''
                message_json = ''
                sock.recv_string(client_id, ZMQ::DONTWAIT)
                sock.recv_string(message_json, ZMQ::DONTWAIT)
                message = JSON.parse message_json

                puts "#{ client_id } ==> #{ message_json }"
                STDOUT.flush

                self.handle_message(sock, client_id, message)

            end
        end
    end

    def handle_message(sock, client_id, message)

        if message['kind'] == 'method'
            self.handle_method(sock, client_id, message)

        else
            # TODO: Handle other message kinds
            puts "Unrecognized message: #{ message }"
        end

    end

    # Handlers
    # --------------------------------------------------------------------------

    def handle_method(sock, client_id, message)

        # Find the method
        if method_proc = @methods[message['method'].to_sym]

            # Create a respond callback
            respond = -> (_response) {
                response = {"id"=> message['id'], "kind"=> "response", "response"=>_response}
                sock.send_string(client_id, ZMQ::SNDMORE)
                sock.send_string(response.to_json)
            }

            # Call the method with the respond callback
            method_proc.call(message['args'], respond)

        # If such a method doesn't exist
        else
            puts @methods
        end

    end

    # Service registration and health checking
    # --------------------------------------------------------------------------

    def register
        registration = {
            'Name' => @name,
            'Port' => @options['bind_port'],
            'Check' => {
                'Interval' => 60,
                'TTL' => '10s'
            }
        }
        req = Net::HTTP::Get.new(
            'http://localhost:8500/v1/agent/service/register',
            initheader={'Content-Type' => 'application/json'}
        )
        req.body = registration.to_json
        @http.request(req)
        puts "Registered service `lifx`"
    end

    def pass_check
        puts "Passing check `service:lifx`"
        req = Net::HTTP::Get.new(
            'http://localhost:8500/v1/agent/check/pass/service:lifx'
        )
        @http.request(req)
    end

    def pass_checks_loop
        while true do
            sleep(5)
            self.pass_check
        end
    end

    def deregister
        puts "TODO"
    end

end

