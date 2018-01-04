require 'spec_helper'

describe 'Fluent::LogzioOutputBuffered' do
  let(:driver) { Fluent::Test::Driver::Output.new(Fluent::LogzioOutputBuffered).configure(config) }
  let(:config) do
    %[
      endpoint_url         https://logz.io?token=123
      output_include_time  false
      bulk_limit           52
    ]
  end

  include_context 'output context'
  include_examples 'output examples'

  describe 'feed' do
    before(:each) do
      expect(request).to receive(:body=).with('{"field1":50,"otherfield":99,"fluentd_tags":"test"}').once
      expect(Net::HTTP::Post).to receive(:new).with('/?token=123').once.and_return(request)
      expect_any_instance_of(Net::HTTP::Persistent).to receive(:request).once.and_return(response)
    end

    it 'adds messages to the buffer' do
      driver.run(default_tag: 'test') do
        driver.feed(time, record1)
        driver.feed(time, record2)
      end

      expect(driver.formatted).to eq([['test', 0.0, {'field1' => 50, 'otherfield' => 99}].to_msgpack,
                                      ['test', 0.0, {'field1' => 150, 'otherfield' => 199}].to_msgpack])
    end
  end
end
