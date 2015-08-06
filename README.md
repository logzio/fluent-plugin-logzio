Logz.io plugin for [Fluentd](http://www.fluentd.org)
=============
With fluent-plugin-logzio you will be able to use [Logz.io](http://logz.io) as output the logs you collect with Fluentd.

## Getting Started
* Install [Fluentd](http://www.fluentd.org/download)
* gem install fluent-plugin-logzio
* Make sure you have an account with Logz.io.
* Configure Fluentd as below:
~~~~
    <match your_match>
      type logzio
      endpoint_url http://listener.logz.io:8090?token=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
    </match>
~~~~
or if you want to use buffered plugin:
~~~~
    <match your_match>
      type logzio_buffered
      endpoint_url http://listener.logz.io:8090?token=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
      output_include_time true  # add 'timestamp' record into log. (default: true)
      buffer_type    file
      buffer_path    /path/to/buffer/file
      flush_interval 10s
    </match>
~~~~

Note that buffered plugin uses bulk import to improve performance, so make sure to set Bulk endpoint to endpoint_url.

The `xxx-xxxx...` is your Logz.io access token.

## Parameters
**endpoint_url** the url to your Logz.io input (string).
