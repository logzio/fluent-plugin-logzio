require 'spec_helper'

describe 'Fluent::LogzioOutputBuffered' do
  let(:driver) { Fluent::Test::BufferedOutputTestDriver.new(Fluent::LogzioOutputBuffered).configure(config) }
  let(:config) do
    %[
      endpoint_url         https://logz.io?token=123
      output_include_time  false
    ]
  end

  include_context 'output context'
  include_examples 'output examples'

  describe 'emit' do
    before(:each) do
      expect(request).to receive(:body=).with('{"field1":50,"otherfield":99}\n{"field1":150,"otherfield":199}')
      expect(Net::HTTP::Post).to receive(:new).with('/?token=123').once.and_return(request)
      expect_any_instance_of(Net::HTTP::Persistent).to receive(:request).once.and_return(response)
    end

    it 'adds messages to the buffer' do
      driver.emit(record1, time)
      driver.emit(record2, time)

      driver.expect_format ['test', 0, { 'field1' => 50, 'otherfield' => 99 }].to_msgpack
      driver.expect_format ['test', 0, { 'field1' => 150, 'otherfield' => 199 }].to_msgpack

      driver.run
    end
  end
end
