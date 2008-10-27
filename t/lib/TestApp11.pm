package TestApp11;

use Moose;
extends 'Sanguine';

# Prevent output to STDOUT
$ENV{CGI_APP_RETURN_ONLY} = 1;

override setup => sub {
    my $self = shift;
    $self->run_modes( mode1 => "mode1" );
    $self->start_mode( 'mode1' );
    $self->error_mode( 'error' );
};


sub mode1 {
    my $self = shift;

    confess "mode1 failed!\n";
}

sub error {
    my $self = shift;
    my ($error) = @_;

    return "Success! Received '$error'";
}

1;
