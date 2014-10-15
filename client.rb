require 'ffi-rzmq'
require 'json'

ctx = ZMQ::Context.new
socket = ctx.socket(ZMQ::DEALER)
socket.identity = "testing"
socket.connect('tcp://127.0.0.1:5555')

while true do
    message = {
        'kind' => 'method',
        'method' => 'set_rgb',
        'args' => gets.strip!.split(' ').map {|x| x.to_f}
    }.to_json
    puts "Sending: " + message
    socket.send_string message
end

