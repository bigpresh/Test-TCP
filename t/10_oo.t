use warnings;
use strict;
use Test::More tests => 22;
use Test::TCP;
use IO::Socket::INET;
use t::Server;

my $server = Test::TCP::OO->new(
    code => sub {
        my $port = shift;
        ok $port, "test case for sharedfork" for 1..10;
        t::Server->new($port)->run(sub {
            note "new request";
            my ($remote, $line, $sock) = @_;
            print {$remote} $line;
        });
    }
);

ok $server->port, "test case for sharedfork" for 1..10;
my $sock = IO::Socket::INET->new(
    PeerPort => $server->port,
    PeerAddr => '127.0.0.1',
    Proto    => 'tcp'
) or die "Cannot open client socket: $!";

note "send 1";
print {$sock} "foo\n";
my $res = <$sock>;
is $res, "foo\n";

note "send 2";
print {$sock} "bar\n";
my $res2 = <$sock>;
is $res2, "bar\n";

note "finalize";
print {$sock} "quit\n";

done_testing;

