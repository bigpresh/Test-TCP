package Test::TCP;
use strict;
use warnings;
use 5.00800;
our $VERSION = '1.07';
use base qw/Exporter/;
use IO::Socket::INET;
use Test::SharedFork 0.12;
use Test::More ();
use Config;
use POSIX;
use Time::HiRes ();

our @EXPORT = qw/ empty_port test_tcp wait_port /;

sub empty_port {
    my $port = do {
        if (@_) {
            my $p = $_[0];
            $p = 19000 unless $p =~ /^[0-9]+$/ && $p < 19000;
            $p;
        } else {
            10000 + int(rand()*1000);
        }
    };

    while ( $port++ < 20000 ) {
        next if _check_port($port);
        my $sock = IO::Socket::INET->new(
            Listen    => 5,
            LocalAddr => '127.0.0.1',
            LocalPort => $port,
            Proto     => 'tcp',
            (($^O eq 'MSWin32') ? () : (ReuseAddr => 1)),
        );
        return $port if $sock;
    }
    die "empty port not found";
}

sub test_tcp {
    my %args = @_;
    for my $k (qw/client server/) {
        die "missing madatory parameter $k" unless exists $args{$k};
    }
    my $server = Test::TCP::OO->new(
        code => $args{server},
        port => $args{port} || empty_port(),
    );
    $args{client}->($server->port, $server->pid);
    undef $server; # make sure
}

sub _check_port {
    my ($port) = @_;

    my $remote = IO::Socket::INET->new(
        Proto    => 'tcp',
        PeerAddr => '127.0.0.1',
        PeerPort => $port,
    );
    if ($remote) {
        close $remote;
        return 1;
    }
    else {
        return 0;
    }
}

sub wait_port {
    my $port = shift;

    my $retry = 100;
    while ( $retry-- ) {
        return if _check_port($port);
        Time::HiRes::sleep(0.1);
    }
    die "cannot open port: $port";
}

package Test::TCP::OO;
use Config;
use Carp ();

# process does not die when received SIGTERM, on win32.
my $TERMSIG = $^O eq 'MSWin32' ? 'KILL' : 'TERM';

sub new {
    my $class = shift;
    my %args = @_==1 ? %{$_[0]} : @_;
    Carp::croak("missing mandatory parameter 'code'") unless exists $args{code};
    my $self = bless {
        auto_start => 1,
        _my_pid    => $$,
        %args,
    }, $class;
    $self->{port} = Test::TCP::empty_port() unless exists $self->{port};
    $self->start()
      if $self->{auto_start};
    return $self;
}

sub pid  { $_[0]->{pid} }
sub port { $_[0]->{port} }

sub start {
    my $self = shift;
    if ( my $pid = fork() ) {
        # parent.
        Test::TCP::wait_port($self->port);
        $self->{pid} = $pid;
        return;
    } elsif ($pid == 0) {
        # child process
        $self->{code}->($self->port);
        exit 0;
    } else {
        die "fork failed: $!";
    }
}

sub DESTROY {
    my $self = shift;

    return unless defined $self->{pid};
    return unless $self->{_my_pid} == $$;

    kill $TERMSIG => $self->{pid};
    local $?; # waitpid modifies original $?.
    LOOP: while (1) {
        my $kid = waitpid( $self->{pid}, 0 );
        if ($^O ne 'MSWin32') { # i'm not in hell
            if (POSIX::WIFSIGNALED($?)) {
                my $signame = (split(' ', $Config{sig_name}))[POSIX::WTERMSIG($?)];
                if ($signame =~ /^(ABRT|PIPE)$/) {
                    Test::More::diag("your server received SIG$signame");
                }
            }
        }
        if ($kid == 0 || $kid == -1) {
            last LOOP;
        }
    }
}

1;
__END__

=encoding utf8

=head1 NAME

Test::TCP - testing TCP program

=head1 SYNOPSIS

    use Test::TCP;
    test_tcp(
        client => sub {
            my ($port, $server_pid) = @_;
            # send request to the server
        },
        server => sub {
            my $port = shift;
            # run server
        },
    );

using other server program

    use Test::TCP;
    test_tcp(
        client => sub {
            my $port = shift;
            # send request to the server
        },
        server => sub {
            exec '/foo/bar/bin/server', 'options';
        },
    );

Or, OO-ish interface

    use Test::TCP;

    my $server = Test::TCP::OO->new(
        code => sub {
            my $port = shift;
            ...
        },
    );
    my $client = MyClient->new(host => '127.0.0.1', port => $server->port);
    undef $server; # kill child process on DESTROY

=head1 DESCRIPTION

Test::TCP is test utilities for TCP/IP program.

=head1 METHODS

=over 4

=item empty_port

    my $port = empty_port();

Get the available port number, you can use.

=item test_tcp

    test_tcp(
        client => sub {
            my $port = shift;
            # send request to the server
        },
        server => sub {
            my $port = shift;
            # run server
        },
        # optional
        port => 8080
    );

=item wait_port

    wait_port(8080);

Waits for a particular port is available for connect.

=back

=head1 Test::TCP::OO

=over 4

=item my $server = Test::TCP::OO->new(%args);

Create new instance of Test::TCP::OO.

Arguments are following:

=over 4

=item $args{auto_start}: Boolean

Call C<< $server->start() >> after create instance.

Default: true

=item $args{code}: CodeRef

The callback function. Argument for callback function is: C<< $code->($pid) >>.

This parameter is required.

=back

=item $server->start()

Start the server process. Normally, you don't need to call this method.

=item my $pid = $server->pid();

Get the pid of child process.

=item my $port = $server->port();

Get the port number of child process.

=back

=head1 FAQ

=over 4

=item How to invoke two servers?

You can call test_tcp() twice!

    test_tcp(
        client => sub {
            my $port1 = shift;
            test_tcp(
                client => sub {
                    my $port2 = shift;
                    # some client code here
                },
                server => sub {
                    my $port2 = shift;
                    # some server2 code here
                },
            );
        },
        server => sub {
            my $port1 = shift;
            # some server1 code here
        },
    );

Or use OO-ish interface instead.

    my $server1 = Test::TCP::OO->new(code => sub {
        my $port1 = shift;
        ...
    });
    my $server2 = Test::TCP::OO->new(code => sub {
        my $port2 = shift;
        ...
    });

    # your client code here.
    ...

=back

=head1 AUTHOR

Tokuhiro Matsuno E<lt>tokuhirom@gmail.comE<gt>

=head1 THANKS TO

kazuhooku

dragon3

charsbar

Tatsuhiko Miyagawa

lestrrat

=head1 SEE ALSO

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
