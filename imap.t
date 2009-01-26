#!/usr/bin/perl

# (C) Maxim Dounin

# Tests for nginx mail imap module.

###############################################################################

use warnings;
use strict;

use Test::More;

use IO::Socket;
use MIME::Base64;
use Socket qw/ CRLF /;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;
use Test::Nginx::IMAP;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()
	->has('mail')->plan(8)
	->run_daemon(\&Test::Nginx::IMAP::imap_test_daemon)
	->write_file_expand('nginx.conf', <<'EOF')->run();

master_process off;
daemon         off;

events {
}

mail {
    proxy_pass_error_message  on;
    auth_http  http://127.0.0.1:8080/mail/auth;

    server {
        listen     127.0.0.1:8143;
        protocol   imap;
        smtp_auth  login plain;
    }
}

http {
    access_log    off;

    client_body_temp_path  %%TESTDIR%%/client_body_temp;
    fastcgi_temp_path      %%TESTDIR%%/fastcgi_temp;
    proxy_temp_path        %%TESTDIR%%/proxy_temp;

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location = /mail/auth {
            set $reply ERROR;

            if ($http_auth_smtp_to ~ example.com) {
                set $reply OK;
            }

            set $userpass "$http_auth_user:$http_auth_pass";
            if ($userpass ~ '^test@example.com:secret$') {
                set $reply OK;
            }

            add_header Auth-Status $reply;
            add_header Auth-Server 127.0.0.1;
            add_header Auth-Port 8144;
            add_header Auth-Wait 1;
            return 204;
        }
    }
}

EOF

###############################################################################

my $s = Test::Nginx::IMAP->new();
$s->ok('greeting');

# auth plain

$s->send('1 AUTHENTICATE PLAIN ' . encode_base64("\0test\@example.com\0bad", ''));
$s->check(qr/^\S+ NO/, 'auth plain with bad password');

$s->send('1 AUTHENTICATE PLAIN ' . encode_base64("\0test\@example.com\0secret", ''));
$s->ok('auth plain');

# auth login simple

$s = Test::Nginx::IMAP->new();
$s->read();

$s->send('1 AUTHENTICATE LOGIN');
$s->check(qr/\+ VXNlcm5hbWU6/, 'auth login username challenge');

$s->send(encode_base64('test@example.com', ''));
$s->check(qr/\+ UGFzc3dvcmQ6/, 'auth login password challenge');

$s->send(encode_base64('secret', ''));
$s->ok('auth login simple');

# auth login with username

TODO: {
local $TODO = 'not supported yet';

$s = Test::Nginx::IMAP->new();
$s->read();

$s->send('1 AUTHENTICATE LOGIN ' . encode_base64('test@example.com', ''));
$s->check(qr/\+ UGFzc3dvcmQ6/, 'auth login with username password challenge');

$s->send(encode_base64('secret', ''));
$s->ok('auth login with username');

}

###############################################################################
