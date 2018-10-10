[![Gem Version](https://badge.fury.io/rb/fluent-plugin-logzio.svg)](https://badge.fury.io/rb/fluent-plugin-logzio)

Logz.io plugin for [Fluentd](http://www.fluentd.org)
=============
With fluent-plugin-logzio you will be able to use [Logz.io](http://logz.io) as output the logs you collect with Fluentd.

## Requirements

| fluent-plugin-logzio      | Fluentd     | Ruby   |
|---------------------------|-------------|--------|
| >= 0.0.15                 | >= v0.14.0  | >= 2.1 |
|  < 0.0.15                 | >= v0.12.0  | >= 1.9 |

## Getting Started
* Install [Fluentd](http://www.fluentd.org/download)
* gem install fluent-plugin-logzio
* Make sure you have an account with Logz.io.
* Configure Fluentd as below:

### FluentD 1.0-style Example Configuration

This is an **example** only. Your needs in production may vary!

```
    <match **>
      @type logzio_buffered

      endpoint_url https://listener.logz.io:8071?token=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx&type=my_type

      output_include_time true
      output_include_tags true
      http_idle_timeout 10

      <buffer>
          @type memory
          flush_thread_count 4
          flush_interval 3s
          chunk_limit_size 16m      # Logz.io bulk limit is decoupled from chunk_limit_size. Set whatever you want.
          queue_limit_length 4096
      </buffer>
    </match>
```

### FluentD 0.12-style Example Configuration

This is an **example** only. Your needs in production may vary!

```
    <match your_match>
      @type logzio_buffered
      endpoint_url https://listener.logz.io:8071?token=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx&type=my_type
      output_include_time true
      output_include_tags true
      output_tags_fieldname @log_name
      buffer_type    file
      buffer_path    /path/to/buffer/file
      flush_interval 10s
      buffer_chunk_limit 64m   # Logz.io bulk limit is decoupled from buffer_chunk_limit. Set whatever you want.
    </match>
```

## Parameters
* **endpoint_url** the url to Logz.io input where `xxx-xxxx...` is your Logz.io access token, and `my_type` is the type of your logs in Logz.io.
* **output_include_time** should the appender add a timestamp to your logs on their process time. (recommended).
* **output_include_tags** should the appender add the fluentd tag to the document, called "fluentd_tag" (which can be renamed, see next point).
* **output_tags_fieldname** set the tag's fieldname, defaults to "fluentd_tag".
* **http_idle_timeout** timeout in seconds that the http persistent connection will stay open without traffic.
* **retry_count** How many times to resend failed bulks. Defaults to 4 times.
* **retry_sleep** How long to sleep initially between retries, exponential step-off. Initial default is 2s.
* **bulk_limit** Limit to the size of the Logz.io upload bulk. Defaults to 1000000 bytes leaving about 24kB for overhead.
* **bulk_limit_warning_limit** Limit to the size of the Logz.io warning message when a record exceeds bulk_limit to prevent a recursion when Fluent warnings are sent to the Logz.io output.  Defaults to nil (no truncation).

## Release Notes
- 0.0.18: Support proxy_uri and proxy_cert in the configuration file. Put logzio output plugin class under Fluent::Plugin module and thus work with multi workers.
- 0.0.17: Optional truncate log messages when they are exceeding bulk size in warning logs
- 0.0.16: More fluentD 1.0+ adjustments
- 0.0.15: Support FluentD 1.0+. Split the chunk into bulk uploads, decoupling `chunk_limit_size`/`buffer_chunk_limit` from Logz.io bulk limit. Tunable `bulk_limit` and initial `retry_sleep`.
- 0.0.14: Refactor send function to handle more cases, and retry in case of logzio connection failure.
- 0.0.13: BREAKING - Removed non-buffered version. It's really not efficient, and should just not be used. If you are using this version, you should change to the buffered one.
- 0.0.12: Catch exception when parsing YAML to ignore (instead of crash) not valid logs.
