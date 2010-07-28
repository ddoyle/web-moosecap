package Web::MooseCap::Role::Stash;

use Moose::Role;

use namespace::autoclean -also => qr/^_/;

requires qw/
    cgiapp_prerun
    query
/;

###################
# the stash
has '_stash' => (
    traits      => [qw/Hash/],
    is          => 'rw',
    isa         => 'HashRef',
    default     => sub { +{} },
    handles     => {
        stash_clear         => 'clear',
        stash_is_empty      => 'is_empty',
        stash_delete_key    => 'delete',
        _stash_set          => 'set',
        _stash_get          => 'get',
    },
);

# stash is reset before cgiapp_prerun
sub stash {
    my $self = shift;
    
    # if they want the hashref
    return $self->_stash() if scalar @_ == 0;

    # if they want to fetch a particular key ...
    return $self->_stash_get($_[0]) if scalar @_ == 1 && !ref $_[0];
   
    $self->_stash_set( ref $_[0] eq 'HASH' ? %{$_[0]} : @_ );

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

#
before 'cgiapp_prerun' => sub {
    my $self = shift;
    $self->stash_clear unless $self->stash_is_empty;
    $self->cgiapp_stash_init();
    return;
};

no Moose::Role; 1;
