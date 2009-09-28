package Web::MooseCap::Role::Stash;

use Moose::Role;


###################
# the stash
has '_stash' => (
    is          => 'rw',
    isa         => 'HashRef',
    default     => sub { +{} },
    init_arg    => undef,
);

# stash is reset before cgiapp_prerun
sub stash {
    my $self = shift;
    my @args = @_;
    
    # if they want the hashref
    return $self->_stash() if scalar @_ == 0;

    # if they want to fetch a particular key ...
    return $self->_stash->{$_[0]} if scalar @_ == 1 && ref $_[0] ne 'HASH' ;
   
    $self->merge_into($self->_stash, @_ );

    return;
}

# overide this to add certain elements into the stash
# happens immediately after stash reset and before cgiapp_prerun
# default feeds the CGI object in
sub cgiapp_stash_init {
    my $self = shift;
    $self->stash( query => $self->query() );
    return;
}


no Moose::Role; 1;