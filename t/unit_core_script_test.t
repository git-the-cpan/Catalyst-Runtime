use strict;
use warnings;

use Carp qw(croak);
use FindBin qw/$Bin/;
use lib "$Bin/lib";

use Test::More;
use Test::Fatal;

use Catalyst::Script::Test;
use File::Temp qw/tempfile/;
use IO::Handle;

is run_test('/'), "root index\n", 'correct content printed';
is run_test('/moose/get_attribute'), "42\n", 'Correct content printed for non root action';

done_testing;

sub run_test {
    my $url = shift;

    my ($fh, $fn) = tempfile();

    binmode( $fh );
    binmode( STDOUT );

    {
        local @ARGV = ($url);
        my $i;
        is exception {
            $i = Catalyst::Script::Test->new_with_options(application_name => 'TestApp');
        }, undef, "new_with_options";
        ok $i;
        my $saved;
        open( $saved, '>&'. STDOUT->fileno )
            or croak("Can't dup stdout: $!");
        open( STDOUT, '>&='. $fh->fileno )
            or croak("Can't open stdout: $!");
        eval { $i->run };
        ok !$@, 'Ran ok';

        STDOUT->flush
            or croak("Can't flush stdout: $!");

        open( STDOUT, '>&'. fileno($saved) )
            or croak("Can't restore stdout: $!");
    }

    my $data = do { my $fh; open($fh, '<', $fn) or die $!; local $/; <$fh>; };
    $fh = undef;
    unlink $fn if -r $fn;

    return $data;
}
