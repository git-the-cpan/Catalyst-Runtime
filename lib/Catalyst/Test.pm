package Catalyst::Test;

use strict;
use warnings;

use Catalyst::Exception;
use Catalyst::Utils;
use Class::Inspector;

=head1 NAME

Catalyst::Test - Test Catalyst Applications

=head1 SYNOPSIS

    # Helper
    script/test.pl

    # Tests
    use Catalyst::Test 'TestApp';
    my $content  = get('index.html');           # Content as string
    my $response = request('index.html');       # HTTP::Response object
    my($res, $c) = ctx_request('index.html');   # HTTP::Response & context object

    use HTTP::Request::Common;
    my $response = request POST '/foo', [
        bar => 'baz',
        something => 'else'
    ];

    # Run tests against a remote server
    CATALYST_SERVER='http://localhost:3000/' prove -r -l lib/ t/

    # Tests with inline apps need to use Catalyst::Engine::Test
    package TestApp;

    use Catalyst;

    sub foo : Global {
            my ( $self, $c ) = @_;
            $c->res->output('bar');
    }

    __PACKAGE__->setup();

    package main;

    use Test::More tests => 1;
    use Catalyst::Test 'TestApp';

    ok( get('/foo') =~ /bar/ );

=head1 DESCRIPTION

This module allows you to make requests to a Catalyst application either without
a server, by simulating the environment of an HTTP request using
L<HTTP::Request::AsCGI> or remotely if you define the CATALYST_SERVER
environment variable.

The </get> and </request> functions take either a URI or an L<HTTP::Request>
object.

=head2 METHODS

=head2 $content = get( ... )

Returns the content.

    my $content = get('foo/bar?test=1');

Note that this method doesn't follow redirects, so to test for a
correctly redirecting page you'll need to use a combination of this
method and the L<request> method below:

    my $res = request('/'); # redirects to /y
    warn $res->header('location');
    use URI;
    my $uri = URI->new($res->header('location'));
    is ( $uri->path , '/y');
    my $content = get($uri->path);

=head2 $res = request( ... );

Returns a C<HTTP::Response> object.

    my $res = request('foo/bar?test=1');

=head1 FUNCTIONS

=head2 ($res, $c) = ctx_request( ... );

Works exactly like C<Catalyst::Test::request>, except it also returns the
catalyst context object, C<$c>. Note that this only works for local requests.

=cut

sub import {
    my $self  = shift;
    my $class = shift;

    my ( $get, $request );

    if ( $ENV{CATALYST_SERVER} ) {
        $request = sub { remote_request(@_) };
        $get     = sub { remote_request(@_)->content };
    } elsif (! $class) {
        $request = sub { Catalyst::Exception->throw("Must specify a test app: use Catalyst::Test 'TestApp'") };
        $get     = $request;
    } else {
        unless( Class::Inspector->loaded( $class ) ) {
            require Class::Inspector->filename( $class );
        }
        $class->import;

        $request = sub { local_request( $class, @_ ) };
        $get     = sub { local_request( $class, @_ )->content };
    }

    no strict 'refs';
    my $caller = caller(0);
    
    *{"$caller\::request"}      = $request;
    *{"$caller\::get"}          = $get;
    *{"$caller\::ctx_request"}  = sub { 
        my $me      = ref $self || $self;

        ### throw an exception if ctx_request is being used against a remote
        ### server
        Catalyst::Exception->throw("$me only works with local requests, not remote")     
            if $ENV{CATALYST_SERVER};
    
        ### place holder for $c after the request finishes; reset every time
        ### requests are done.
        my $c;
        
        ### hook into 'dispatch' -- the function gets called after all plugins
        ### have done their work, and it's an easy place to capture $c.
        no warnings 'redefine';
        my $dispatch = Catalyst->can('dispatch');
        local *Catalyst::dispatch = sub {
            $c = shift;
            $dispatch->( $c, @_ );
        };
        
        ### do the request; C::T::request will know about the class name, and
        ### we've already stopped it from doing remote requests above.
        my $res = $request->( @_ );
        
        ### return both values
        return ( $res, $c );
    };
}

=head2 $res = Catalyst::Test::local_request( $AppClass, $url );

Simulate a request using L<HTTP::Request::AsCGI>.

=cut

sub local_request {
    my $class = shift;

    require HTTP::Request::AsCGI;

    my $request = Catalyst::Utils::request( shift(@_) );
    my $cgi     = HTTP::Request::AsCGI->new( $request, %ENV )->setup;

    $class->handle_request;

    return $cgi->restore->response;
}

my $agent;

=head2 $res = Catalyst::Test::remote_request( $url );

Do an actual remote request using LWP.

=cut

sub remote_request {

    require LWP::UserAgent;

    my $request = Catalyst::Utils::request( shift(@_) );
    my $server  = URI->new( $ENV{CATALYST_SERVER} );

    if ( $server->path =~ m|^(.+)?/$| ) {
        my $path = $1;
        $server->path("$path") if $path;    # need to be quoted
    }

    # the request path needs to be sanitised if $server is using a
    # non-root path due to potential overlap between request path and
    # response path.
    if ($server->path) {
        # If request path is '/', we have to add a trailing slash to the
        # final request URI
        my $add_trailing = $request->uri->path eq '/';
        
        my @sp = split '/', $server->path;
        my @rp = split '/', $request->uri->path;
        shift @sp;shift @rp; # leading /
        if (@rp) {
            foreach my $sp (@sp) {
                $sp eq $rp[0] ? shift @rp : last
            }
        }
        $request->uri->path(join '/', @rp);
        
        if ( $add_trailing ) {
            $request->uri->path( $request->uri->path . '/' );
        }
    }

    $request->uri->scheme( $server->scheme );
    $request->uri->host( $server->host );
    $request->uri->port( $server->port );
    $request->uri->path( $server->path . $request->uri->path );

    unless ($agent) {

        $agent = LWP::UserAgent->new(
            keep_alive   => 1,
            max_redirect => 0,
            timeout      => 60,
            
            # work around newer LWP max_redirect 0 bug
            # http://rt.cpan.org/Ticket/Display.html?id=40260
            requests_redirectable => [],
        );

        $agent->env_proxy;
    }

    return $agent->request($request);
}

=head1 SEE ALSO

L<Catalyst>, L<Test::WWW::Mechanize::Catalyst>,
L<Test::WWW::Selenium::Catalyst>, L<Test::More>, L<HTTP::Request::Common>

=head1 AUTHORS

Catalyst Contributors, see Catalyst.pm

=head1 COPYRIGHT

This program is free software, you can redistribute it and/or modify it under
the same terms as Perl itself.

=cut

1;
