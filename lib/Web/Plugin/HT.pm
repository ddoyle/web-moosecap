package Web::MooseCap::Plugin::HT;

use Moose::Role;

use Moose::Util::TypeConstraints;
use MooseX::MultiInitArg;
use Class::MOP;

############################################

# the tmpl path subtype
subtype 'Web::MooseCap::Plugin::HT::tmpl_path'
    => as 'ArrayRef'
    => where { ref $_ eq 'ARRAY' }
    => message { "Invalid tmpl_path specified ($_)" };
 
coerce 'Web::MooseCap::Plugin::HT::tmpl_path'
    => from 'Str'   => via { [ $_ ] }
    => from 'Undef' => via { []     };
        
# default template path includes
has 'tmpl_path' => (
    metaclass   => 'MultiInitArg',
    is          => 'rw',
    isa         => 'Web::MooseCap::Plugin::HT::tmpl_path',
    default     => sub { [] },
    coerce      => 1,
    init_args   => [qw/TMPL_PATH/],
);

# the template extension when we're not given a filename to load_tmpl
has 'tmpl_extension' => (
    metaclass   => 'MultiInitArg',
    is          => 'rw',
    isa         => 'Str',
    default     => '.html',
    init_args   => [ qw/TMPL_EXTENSION/ ],
);

# the default HTML::Template type class used by load_tmpl
has 'html_tmpl_class' => (
    is          => 'rw',
    isa         => 'Str',
    default     => 'HTML::Template',
    init_arg    => undef,
);

sub load_tmpl {
	my $self = shift;
	my ($tmpl_file, @extra_params) = @_;

	# add tmpl_path to path array if one is set, otherwise add a path arg
	if ( scalar @{$self->tmpl_path() } ) {
		my @tmpl_paths = @{$self->tmpl_path};
		my $found = 0;
		for( my $x = 0; $x < @extra_params; $x += 2 ) {
			if ($extra_params[$x] eq 'path' and
			ref $extra_params[$x+1] eq 'ARRAY') {
				unshift @{$extra_params[$x+1]}, @tmpl_paths;
				$found = 1;
				last;
			}
		}
		push(@extra_params, path => [ @tmpl_paths ]) unless $found;
	}

    my %tmpl_params = ();
    my %ht_params = @extra_params;
    %ht_params = () unless keys %ht_params;
    
    # Define a default template name based on the current run mode
    $tmpl_file = $self->get_current_runmode . $self->tmpl_extension
        unless defined $tmpl_file;

    $self->call_hook('load_tmpl', \%ht_params, \%tmpl_params, $tmpl_file);

    my $ht = $self->html_tmpl_class();
    Class::MOP::load_class($ht);

    # let's check $tmpl_file and see what kind of parameter it is - we
    # now support 3 options: scalar (filename), ref to scalar (the
    # actual html/template content) and reference to FILEHANDLE
    my $ref = ref $tmpl_file;
    my $t = $ref eq 'SCALAR' ? $ht->new( scalarref  => $tmpl_file, %ht_params )
          : $ref eq 'GLOB'   ? $ht->new( filehandle => $tmpl_file, %ht_params )
          :                    $ht->new( filename   => $tmpl_file, %ht_params )
          ;

    $t->param(%tmpl_params) if keys %tmpl_params;

	return $t;
}

no Moose::Role; 1;
