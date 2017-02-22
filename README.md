[![Gem Version](https://badge.fury.io/rb/fluent-plugin-logzio.svg)](https://badge.fury.io/rb/fluent-plugin-logzio)

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
      output_include_time true
      output_include_tags true
      output_tags_fieldname @log_name
      buffer_type    file
      buffer_path    /path/to/buffer/file
      flush_interval 10s
      buffer_chunk_limit 1m   # Logz.io has bulk limit of 10M. We recommend set this to 1M, to avoid oversized bulks
    </match>
```

If you absolutly must, use the non-buffered plugin (we really recommend using the buffered)
```
    <match your_match>
      type logzio
      endpoint_url http://listener.logz.io:8090?token=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
    </match>
```

## Parameters
* **endpoint_url** the url to Logz.io input where `xxx-xxxx...` is your Logz.io access token, and `my_type` is the type of your logs in logz.io
* **output_include_time** should the appender add a timestamp to your logs on their process time. (recommended)
* **output_include_tags** should the appender add the fluentd tag to the document, called "fluentd_tag" (which can be renamed, see next point)
* **output_tags_fieldname** set the tag's fieldname, defaults to "fluentd_tag"
* **http_idle_timeout** timeout in seconds that the http persistent connection will stay open without traffic
