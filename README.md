Logz.io plugin for [Fluentd](http://www.fluentd.org)
=============
With fluent-plugin-logzio you will be able to use [Logz.io](http://logz.io) as output the logs you collect with Fluentd.

## Getting Started
* Install [Fluentd](http://www.fluentd.org/download)
* gem install fluent-plugin-logzio
* Make sure you have an account with Logz.io.
* Configure Fluentd as below:

```
    <match your_match>
      type logzio_buffered
      endpoint_url https://listener.logz.io:8071?token=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx&type=my_type
      output_include_time true  # add 'timestamp' record into log. (default: true)
      buffer_type    file
      buffer_path    /path/to/buffer/file
      flush_interval 10s
    </match>
```

If you absolutly must, use the non-buffered plugin (we really recommend using the buffered)
```
    <match your_match>
      type logzio
      endpoint_url http://listener.logz.io:8090?token=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
    </match>
```

The `xxx-xxxx...` is your Logz.io access token, and the "my_type" is the type of your logs in logz.io

## Parameters
**endpoint_url** the url to your Logz.io input (string).
