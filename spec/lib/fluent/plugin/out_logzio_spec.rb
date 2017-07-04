require 'spec_helper'

describe 'Fluent::LogzioOutput' do
  let(:driver) { Fluent::Test::OutputTestDriver.new(Fluent::LogzioOutput).configure(config) }
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
      expect(request).to receive(:body=).with('{"field1":50,"otherfield":99,"fluentd_tags":"test"}')
      expect(request).to receive(:body=).with('{"field1":150,"otherfield":199,"fluentd_tags":"test"}')
      expect(Net::HTTP::Post).to receive(:new).with('/?token=123').twice.and_return(request)
      expect_any_instance_of(Net::HTTP::Persistent).to receive(:request).twice.and_return(response)
    end

    it 'sends http requests' do
      driver.run

      driver.emit(record1, Time.at(time))
      driver.emit(record2, Time.at(time))
    end
  end
end
