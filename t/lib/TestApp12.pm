package TestApp12;

use Moose;
extends 'Web::MooseCap';


override 'setup' => sub {
    my $self = shift;
    $self->run_modes( mode1 => "mode1" );
    $self->start_mode( 'mode1' );
    $self->error_mode( 'error' );
};


sub mode1 {
    my $self = shift;

    die "mode1 failed!\n";
}

sub error {
    my $self = shift;

    die "Oops!\n";
}

__PACKAGE__->meta->make_immutable; no Moose; 1;
