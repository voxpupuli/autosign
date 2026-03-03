# autosign
 [![Dependency Status](https://gemnasium.com/danieldreier/autosign.svg)](https://gemnasium.com/danieldreier/autosign) [![Yard Docs](http://img.shields.io/badge/yard-docs-blue.svg)](http://rubydoc.info/github/danieldreier/autosign) [![Inline docs](http://inch-ci.org/github/danieldreier/autosign.png)](http://inch-ci.org/github/danieldreier/autosign) [![Coverage Status](https://coveralls.io/repos/danieldreier/autosign/badge.svg?branch=master&service=github)](https://coveralls.io/github/danieldreier/autosign?branch=master) [![Gem Version](https://badge.fury.io/rb/autosign.svg)](http://badge.fury.io/rb/autosign)

Tooling to make OpenVox or Puppet autosigning easy, secure, and extensible

## Introduction

This tool provides a CLI for performing OpenVox [policy-based autosigning](https://www.puppet.com/docs/puppet/7/ssl_autosign.html#ssl_policy_based_autosigning) using JWT tokens.

* Generate time-limited, reusable or one-time tokens
* CLI tooling
* Extensive logging

### Project Background

Both OpenVox and Puppet require that agent SSL certificates be signed by the server's certificate authority.
One can sign certificates in several ways:
* Manually using the `puppet cert sign` command on the server
* Via graphical frontends like the Foreman or the PE web console
* Automatically in an insecure way using naive autosigning
* automatically and (potentially) more securely using policy-based autosigning (such as with this tool)

Policy-based autosigning calls an external executable to determine whether or not to sign the certificate signing request (CSR).
The CSR is passed to the executable's `STDIN` and the agent's certificate name is passed as the sole parameter.
Puppet does not profide a default policy autosign executable, so people are expected to write their own.

Over the years, some have been written and released publicly,
such as Chris Barker's [AWS autosign script](https://github.com/mrzarquon/mrzarquon-certsigner) 
or David Lutterkort's [pre-shared key script](http://watzmann.net/blog/2014/06/puppet-autosign-policy.html).
Generally speaking, these are written as one-off scripts, solving only a specific need.

Most simple autosign scripts are based on validating one or more static strings (e.g. passwords, API keys, etc).
Unfortunately, if an attacker can obtain that string they can sign their own certificate and grant themselves access to the Puppet infrastructure.
This means that they can issue valid requests to the Puppet server, potentially allowing them to impersonate secure infrastructure and escalate privileges.
People also frequently forget to delete the `csr_attributes.yaml` after generating a CSR, and as with any plain-text password the tendency is for the keys to be widely distributed.

This tool solves these problems by generating time limited, one-time tokens that are only valid for a specific host, so that obtaining the token after provisioning is not useful to an attacker.

### Functionality

This gem provides functionality in several areas.

1. A JWT-based token system for securely issuing autosign tokens
2. a pluggable architecture for creating new autosign validation tools
3. a CLI for managing autosign tokens
4. multiplexing, allowing one or more existing autosign policy executables to be run as validators

At the moment, if any one validator passes, the CSR is signed.
In the future, we intend to provide the ability to require that all pass, and ideally provide more complex rules.

## Security Model for JWT Tokens

The goal of the JWT tokens is to place time, reusability, and `commonName` constraints on tokens.
There are several expected use models:

### Per-host tokens for automated provisioning

During automated provisioning, a new token can be generated for each provisioned host.
They will only be usable once, and will expire after a time period (2 hours by default).

### Time-limited delegation of signing ability

You can generate a wildcard token that is only valid for hours or days, then share it with another person who needs to provision systems.
Use of the token will be logged, so if you generate individual tokens for different users it's possible to audit who authorized which certificates to be signed.
After the time period expires, they will no longer be able to authorize more hosts, but the previously-authorized hosts continue to work.


## Quick Start: How to Generate Tokens

##### 1. Install Gem on OpenVox server
```shell
gem install autosign
```

##### 2. Generate default configuration

```shell
autosign config setup
```

##### 3. Generate your first autosign token on the OpenVox server
```shell
autosign generate foo.example.com
```

The output will look something like
```
Autosign token for: foo.example.com, valid until: 2015-07-16 16:25:50 -0700
To use the token, put the following in ${puppet_confdir}/csr_attributes.yaml prior to running `puppet agent` for the first time:

custom_attributes:
  challengePassword: "eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzUxMiJ9.eyJkYXRhIjoie1wiY2VydG5hbWVcIjpcImZvby5leGFtcGxlLmNvbVwiLFwicmVxdWVzdGVyXCI6XCJEYW5pZWxzLU1hY0Jvb2stUHJvLTIubG9jYWxcIixcInJldXNhYmxlXCI6ZmFsc2UsXCJ2YWxpZGZvclwiOjcyMDAsXCJ1dWlkXCI6XCJkM2YyNzI0OC1jZDFmLTRhZmItYjI0MC02ZjBjMDU4NWJiZDNcIn0iLCJleHAiOiIxNDM3MDg5MTUwIn0.lC-EzWaV2dL81aLL7P-9mGwNbiOQDJWcoYjuSHVOqmaLtc7Wis5OZvHFOLln2Fn9qv98oSTnZsIkjmFpbI5dvA"
  ```

The resulting output can be copied to `/etc/puppet/csr_attributes.yaml` on an agent machine prior to running puppet for the first time to add the token to the CSR as the `challengePassword` OID. (just copy-paste from one terminal to another to copy the text)

### Quick Start: OpenVox server Configuration

Run through the previous quick start steps to get the gem installed, then configure puppet to use the `autosign-validator` executable as the policy autosign command:

##### 1. Prerequisities
Note that these settings will be slightly different if you're running Puppet Enterprise, because you'll need to use the `pe-puppet` user instead of `puppet`.

```shell
mkdir /var/autosign
chown puppet:puppet /var/autosign
chmod 750 /var/autosign
touch /var/log/autosign.log
chown puppet:puppet /var/log/autosign.log
```


##### 2. Configure server
```shell
puppet config set autosign $(which autosign-validator) --section master
```

Your master is now configured to autosign using the autosign gem. 


##### 3. Using Legacy Autosign Scripts

If you already had an autosign script you want to continue using, add a setting to your `autosign.conf` like:

```yaml
multiplexer:
  external_policy_executable: "/path/to/autosign/executable"
```

The master will validate the certificate if either the token validator or the external validator succeeds.

If the autosign script was just validating simple strings, you can use the `password_list` validator instead. For example, to configure the master to sign any CSR that includes the challenge passwords of "hunter2" or "CPE1704TKS" you would add:

```ini
password_list:
  password: "hunter2"
  password: "CPE1704TKS"
```

Note that this is a relatively insecure way to do certificate autosigning. Using one-time tokens via the `autosign generate` command is more secure. This functionality is provided to grandfather in existing use cases to ease the transition.

## Validation order
By default the validation runs the following validators in order: 

1. jwt_token
2. password_list
3. multiplexer

The first validator to succeed wins and short circuits the validaiton process.

You can completely customize the list and how they are ordered via the configuration file.  Or even remove some entirely.

```
---
general:
  loglevel: debug
  logfile: "/var/log/autosign.log"
  validation_order: 
    - jwt_token
    - multiplexer
    - password_list
jwt_token:
  secret: J7/WjmkC/CJp2K0/8+sktzSgCqQ=
  validity: '7200'
  journalfile: "/root/var/autosign/autosign.journal"
```

The validation_order config is an ordered array and since the validators will only match the first validation
to succeed the validation script should occur as fast as you want.  

Additionally, if you omit any validator that validator will not be used during the validation process.  This might 
be important if you wanted to only use special validators or remove unwanted validator execution.

Please note, the name of the validator which is speficed by the `NAME` constant in the validator code must match
the list you specify otherwise it will not be part of the validation process.

**NOTE** To use this feature you must have deep_merge 1.2.1+ installed which is now a requirement of this gem.

### Troubleshooting
If you're having problems, try the following:

- Set `loglevel: "debug"` in `/etc/autosign.conf`
- Check the `journalfile`, in `/var/autosign/autosign.journal` by default, to see if the one-time token's UUID has already been recorded. It's just YAML, so you can either delete it or remove the offending entry if you actually want to re-use a token.
- you can manually trigger the autosigning script with something like `cat the_csr.csr | autosign-validator certname.example.com`
- If you run the puppet master foregrounded, you'll see quite a bit of autosign script output if autosign loglevel is set to debug.

#### Inspecting JWT expiration
Autosign tokens are JSON Web Tokens. You can paste one into [`jwt.io`](https://www.jwt.io) to see the decoded payload and confirm the `exp` claim that controls expiration.

Prefer staying on the command line? Decode the payload locally and read the `exp` timestamp (seconds since the UNIX epoch):

```shell
token="eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzUxMiJ9.eyJkYXRhIjoie1wiY2VydG5hbWVcIjpcImZvby5leGFtcGxlLmNvbVwiLFwicmVxdWVzdGVyXCI6XCJEYW5pZWxzLU1hY0Jvb2stUHJvLTIubG9jYWxcIixcInJldXNhYmxlXCI6ZmFsc2UsXCJ2YWxpZGZvclwiOjI5OTk5OTk5OSxcInV1aWRcIjpcIjlkYTA0Yzc4LWQ5NjUtNDk2OC04MWNjLWVhM2RjZDllZjVjMFwifSIsImV4cCI6IjE3MzY0NjYxMzAifQ.PJwY8rIunVyWi_lw0ypFclME0jx3Vd9xJIQSyhN3VUmul3V8u4Tp9XwDgoAu9DVV0-WEG2Tfxs6F8R6Fn71Ndg"
ruby -rjson -rbase64 -e '
  payload = ARGV.first.split(".")[1]
  padding = "=" * ((4 - payload.length % 4) % 4)
  decoded = Base64.urlsafe_decode64(payload + padding)
  data = JSON.parse(decoded)
  if data["exp"]
    require "time"
    data["exp_readable"] = Time.at(data["exp"].to_i).utc.iso8601
  end
  puts JSON.pretty_generate(data)
' "$token"
```

The printed JSON includes the `exp` field and an `exp_readable` value you can copy directly.

Starting with the 1.0.0 release the autosign gem requires ruby 2.4.  If you can't upgrade just yet you can continue to use the older 0.1.4 release.

### Further Reading

- Automatically generated code documentation in YARDOC format is [available on rubydoc.info](http://rubydoc.info/github/voxpupuli/autosign).
- Look at the [puppet-autosign](https://github.com/voxpupuli/puppet-autosign) puppet module to automate setup of this tool, and for a puppet function to generate tokens inside of Puppet, for example when provisioning systems in AWS.
