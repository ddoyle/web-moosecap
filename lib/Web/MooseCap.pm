package Web::MooseCap;

use Moose;
use Moose::Util::TypeConstraints;
use MooseX::AttributeHelpers;
use MooseX::ClassAttribute;

use metaclass;

use Class::MOP;
use Clone qw(clone);
use Data::Dumper;
use Params::Validate qw(SCALAR HASHREF ARRAYREF validate validate_pos);
#use Template;

our $VERSION   = '0.01';
our $AUTHORITY = 'cpan:DDOYLE';


############################################

# the tmpl path subtype
subtype 'Web::MooseCap::tmpl_path'
    => as 'ArrayRef'
    => where { ref $_ eq 'ARRAY' }
    => message { "Invalid tmpl_path specified ($_)" };
 
coerce 'Web::MooseCap::tmpl_path'
    => from 'Str'   => via { [ $_ ] }
    => from 'Undef' => via { []     };
        
# default template path includes
has 'tmpl_path' => (
    is      => 'rw',
    isa     => 'Web::MooseCap::tmpl_path',
    default => sub { [] },
    coerce  => 1,
);


###############################################
# Simple Attributes

# what header to send out (none is useful for running from command line)
has 'header_type' => (
    is          => 'rw',
    isa         => enum([ qw/header redirect none/ ]),
    default     => 'header',
    init_arg    => undef,
);

# start_mode - the default starting runmode for the app
has 'start_mode' => (
    is          => 'rw',
    isa         => 'Str',
    default     => 'start',
    init_arg    => undef,
);

# the default HTML::Template type class used by load_tmpl
has 'html_tmpl_class' => (
    is          => 'rw',
    isa         => 'Str',
    default     => 'HTML::Template',
    init_arg    => undef,
);

# The query object, compatible with CGI/CGI::Simple
has 'query' => (
    is          => 'rw',
    isa         => 'Object',
    lazy        => 1,
    builder     => 'cgiapp_get_query',
);

# the name of the error mode
has 'error_mode' => (
    is          => 'rw',
    isa         => 'Str',
    default     => '',
    init_arg    => undef,
);

# accessor/mutator for the getting/setting the runmode in cgiapp_prerun
# trigger is to ensure you're only doing it while in cgiapp_prerun
has 'prerun_mode' => (
    is          => 'rw',
    isa         => 'Str',
    default     => '',
    trigger     => sub {
        confess("prerun_mode() can only be called within cgiapp_prerun()!  Error")
            if $_[0]->_prerun_mode_locked();
    }
);



#########################################
# PRIVATE ATTRIBUTES

# this is to determine the mode param
has '_mode_param' => (
    is          => 'rw',
    isa         => 'Any',
    default => 'rm',
    init_arg => undef,
);

# cache item to remember callback classes checked so we don't have to do the
# expensive $app_class->meta->class_precedence_list every time
has '_superclass_cache' => (
    is          => 'rw',
    isa         => 'ArrayRef[Str]',
    default     => sub { [] },
    init_arg    => undef,
);

# the template extension when we're not given a filename to load_tmpl
has 'tmpl_extension' => (
    is          => 'rw',
    isa         => 'Str',
    default     => '.html',
);

has '_prerun_mode_locked' => (
    is          => 'rw',
    isa         => 'Bool',
    default     => 1,
    init_arg    => undef,
);

# stores/sets the current runmode
has '_current_runmode' => (
    isa         => 'Str',
    reader      => 'get_current_runmode',  # public
    writer      => '_set_current_runmode', # private
    init_arg    => undef,
);

# headers to output for a request
has '_header_props' => (
    metaclass   => 'Collection::Hash',
    is          => 'rw',
    isa         => 'HashRef',
    default     => sub { +{} },
    provides    => {
        clear   => '_header_props_clear',
        set     => '_header_props_set',
        get     => '_header_props_get',
    },
);

##############
# callback related attribs

# list of installed callbacks on the instance
has '_instance_callbacks' => (
    is          => 'rw',
    isa         => 'HashRef',
    default     => sub { +{} },
);


# base list of callback hooks for the class
class_has '_class_callbacks' => (
    is          => 'rw',
    isa         => 'HashRef',
    default     => sub { return {
    #	hook name            package         sub
        init            => { 'Web::MooseCap' => [ 'cgiapp_init'       ] },
        stash_init      => { 'Web::MooseCap' => [ 'cgiapp_stash_init' ] },
        prerun          => { 'Web::MooseCap' => [ 'cgiapp_prerun'     ] },
        postrun         => { 'Web::MooseCap' => [ 'cgiapp_postrun'    ] },
        teardown        => { 'Web::MooseCap' => [ 'teardown'          ] },
        load_tmpl       => { },
        tt              => { }, # hook for adding to tt tmplvars and options
        error           => { },
        forward_prerun  => { },
    } },
);


###################
# CGI.pm param-like method

has 'params' => (
    is          => 'rw',
    isa         => 'HashRef',
    lazy_build  => 1,
    builder     => 'init_params',
    metaclass   => 'Collection::Hash',
    provides    => { delete  => 'delete', }, # del-a-key-from-param-hash method
);

sub init_params { +{} }

sub param {
    my $self = shift;
    
    # if they want the list of keys ...
    return keys %{$self->params}  if scalar @_ == 0;

    # if they want to fetch a particular key ...
    return $self->params->{$_[0]} if scalar @_ == 1 && ref $_[0] ne 'HASH';

    # merge data in
    $self->merge_into($self->params, @_ );

    # if we're setting exactly one param, return it
    return scalar @_ == 2 ? $_[1] : undef;
}


###################
# the stash
has '_stash' => (
    is          => 'rw',
    isa         => 'HashRef',
    default     => sub { +{} },
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

#######################
# tt with stash integration

sub merge_into {
    my $self = shift;
    my $hash = shift || {};
    
    confess "must pass a hashref" unless ref $hash eq 'HASH';
    
    if (ref $_[0] eq 'HASH') {
        $hash->{$_} = $_[0]->{$_} foreach keys %{$_[0]};
        return $hash;
    }
    
    confess "parameter assignment must be an even numbered list" unless
        ((scalar @_ % 2) == 0 );
    
    my %new = @_;
    
    while( my ($key, $value) = each %new ) {
        $hash->{$key} = $value;
    }
    
    return $hash;
    
}


has '__tt' => (
    is          => 'rw',
    isa         => 'Template',
    lazy        => 1,
    builder     => '__tt_build',
);


# tt builder
sub tt_options {
    my $self = shift;
    
    my $hash = {
        POST_CHOMP => 1,
        template_extension => $self->tmpl_extension,
    };
    
    $hash->{INCLUDE_PATH} = $self->tmpl_path if scalar @{ $self->tmpl_path };

    # merge any args so we can do an 'arround' method modifier later
    $self->merge_into( $hash, @_ );

    return $hash;
}

sub __tt_build {
    my $self = shift;
    
    require Template;
    return Template->new($self->tt_options)
        || confess 'Failed to create template';
}



sub tt {
    my $self = shift;
    
    my @args = @_;
    @args = ( 'tmpl' => $args[0] ) if scalar(@args) == 1;
    my %args = validate(@args,{
        tmpl    => {                  default => $self->get_current_runmode() },
        params  => { type => HASHREF, default => {}                           },
        options => { type => HASHREF, default => {}                           },
    });
                        
    # generate the data to populate the template with
    # this includes the stash and any user provided tmpl_params
    my $params = $self->merge_into( {}, $self->stash() );
    $self->merge_into($params, $args{params});
    
    # tmpl may be a scallarref containing the template
    #             a scalar with the name of the file to load (less the template ext)
    my $tmpl = $args{tmpl};

    # call the hook so you can further modify the tt_params, tmpl_params and
    # the template itself
    $self->call_hook('tt', \$tmpl, $params );

    my $html = '';
    $self->__tt->process( $tmpl, $params, \$html, $args{options} );
    
    return \$html; # return ref for efficiancy
}


######################
# Runmode attribute + getter/setter
# Hashref of valid runmodes
has '_run_modes' => (
    is          => 'rw',
    isa         => 'HashRef',
    default     => sub { +{} },
);

sub run_modes {
	my $self = shift;
	my (@data) = (@_);

    # return the hashref if no args
    return $self->_run_modes() unless scalar @data;

    # handle the various formats of input
    if    (ref($data[0]) eq 'HASH')  { @data = %{$data[0]};                  }
    elsif (ref($data[0]) eq 'ARRAY') { @data = map { $_ => $_ } @{$data[0]}; }
    elsif ((scalar(@data) % 2) != 0) {
        confess("Odd number of elements passed to run_modes().  Not a valid hash");
    }
    $self->_run_modes({%{$self->_run_modes()}, @data});

	# If we've gotten this far, return the value!
	return $self->_run_modes(); 
}

###############################################
# the builder/constructor
sub BUILD {
	my ($self, $params) = @_;

    
	# Call cgiapp_init() method, which may be implemented in the sub-class.
	# Pass all constructor args forward.  This will allow flexible usage
	# down the line.
	$self->call_hook('init', (%{$params}));

	# Call setup() method, which should be implemented in the sub-class!
	$self->setup();
}


################################################
# originally from CAP::Plugins::Forward by Michael Graham
#
# forwards from one runmode to another while maintaing the current runmode
# state.  This is instead of calling $self->other_run_mode in a runmode.
sub forward {
    my $self     = shift;
    my $run_mode = shift;

    my $rm_map = $self->run_modes;
    
    confess "forward: run mode $run_mode does not exist"
        unless exists $rm_map->{$run_mode};

    my $method = $rm_map->{$run_mode};

    if ($self->can($method) || ref $method eq 'CODE') {
        $self->_set_current_runmode( $run_mode );
        $self->call_hook('forward_prerun');
        return $self->$method(@_);
    }

    confess "forward: target method $method of run mode $run_mode does not exist";
}

##############################
# originally from CGI::Application::Plugin::Forward by Cees Hek
#
# all in one magical redirect
sub redirect {
    my $self     = shift;
    my ($location, $status) = (@_);

    # The eval may fail, but we don't care
    eval {
        $self->run_modes( dummy_redirect => sub { } );
        $self->prerun_mode('dummy_redirect');
    };

    if ($status) {
        $self->header_add( -location => $location, -status => $status );
    } else {
        $self->header_add( -location => $location );
    }
    $self->header_type('redirect');
    return;

}

###################################
####  INSTANCE SCRIPT METHODS  ####
###################################

# called by RUN to determine the runmode
sub __get_runmode {
	my $self     = shift;
	my $rm_param = shift;

	# Support call-back instead of CGI mode param
	my $rm = ref($rm_param) eq 'CODE' ? $rm_param->($self)             # Get run mode from subref
           : ref($rm_param) eq 'HASH' ? $rm_param->{run_mode}          # support setting run mode from PATH_INFO
           :                            $self->query->param($rm_param) # Get run mode from CGI param
           ;
    
	# If $rm undefined, use default (start) mode
	$rm = $self->start_mode unless defined($rm) && length($rm);

	return $rm;
}

# called by __get_body to determine the
# runmode. returns coderef
sub __get_runmeth {
	my $self = shift;
	my $rm   = shift;

	my $runmode_method;

    my $is_autoload = 0; # flag whether or not we end up using AUTOLOAD 

	my $runmodes = $self->run_modes();

    # Default: runmode is stored and is not an autoload method
    return ( $runmodes->{$rm}, $is_autoload)
        if exists $runmodes->{$rm};

    # Look for run mode "AUTOLOAD" before dieing
    confess("No such run mode '$rm'")
        unless exists $runmodes->{'AUTOLOAD'};

    $runmode_method = $runmodes->{'AUTOLOAD'};
    $is_autoload = 1;

	return ($runmode_method, $is_autoload);
}


# this is executed by sub run to actually assemble the page
sub __get_body {
	my $self  = shift;
	my $rm    = shift;

	my ($runmode_method, $is_autoload) = $self->__get_runmeth($rm);

    #$self->dump( { rm_meth => $runmode_method, rm =>$rm });

	my $body;
    
    # see if we can run the runmode
	eval {
        $body = $is_autoload
              ? $self->$runmode_method($rm)
              : $self->$runmode_method();
	};
    
    # on error, call the appropriate hook
	if ($@) {
		my $error = $@;
		$self->call_hook('error', $error);
		if (my $em = $self->error_mode) {
			$body = $self->$em( $error );
		} else {
			confess("Error executing run mode '$rm': $error");
		}
	}

	# Make sure that $body is not undefined (suppress 'uninitialized value'
	# warnings)
	return defined $body ? $body : '';
}

# get/set the mode_parameter
sub mode_param {
	my $self = shift;
	my $mode_param;

	my %p;
    
    #die "PATHINFO!\n";
	# expecting a scalar or code ref
	if ((scalar @_) == 1) {
        $mode_param = $_[0];
        #print "SCALAR SET\n";
	}
	# expecting hash style params
	else {
        
		confess "Web::MooseCap->mode_param() : You gave me an odd number of parameters to mode_param()!"
            unless ((@_ % 2) == 0);
		%p = @_;
		$mode_param = $p{param};

		if ( $p{path_info} && $self->query->path_info() ) {
            
            #print "PATHINFO SET\n";
			my $path_info = $self->query->path_info();

			my $index = $p{path_info};
			# two cases: negative or positive index
			# negative index counts from the end of path_info
			# positive index needs to be fixed because 
			#    computer scientists like to start counting from zero.
			$index -= 1 if ($index > 0) ;	

			# remove the leading slash
			$path_info =~ s!^/!!;

			# grab the requested field location
			$path_info = (split q'/', $path_info)[$index] || '';

			$mode_param = (length $path_info)            # if the path has a length
                        ?  { run_mode => $path_info }    # return a hash with the run_mode
                        : $mode_param;                   # otherwise just set the mode_param as normal
		}

	}

	# If data is provided, set it
    $self->_mode_param( $mode_param )
        if defined $mode_param
            && (
                    ref $mode_param eq 'CODE'
                 || ref $mode_param eq 'HASH'
                 || length $mode_param
            );
        
	return $self->_mode_param();
}

# meat of the work done here
sub run {
	my $self = shift;
	my $q = $self->query();

	my $rm_param = $self->mode_param();

	my $rm = $self->__get_runmode($rm_param);

	# Set get_current_runmode() for access by user later
    $self->_set_current_runmode($rm);

    # reset the stash
    $self->_stash({});
    $self->call_hook('stash_init');

	# Allow prerun_mode to be changed
    $self->_prerun_mode_locked(0);

	# Call PRE-RUN hook, now that we know the run mode
	# This hook can be used to provide run mode specific behaviors
	# before the run mode actually runs.
 	$self->call_hook('prerun', $rm);

	# Lock prerun_mode from being changed after cgiapp_prerun()
    $self->_prerun_mode_locked(1);

	# If prerun_mode has been set, use it!
	my $prerun_mode = $self->prerun_mode();
	if (length($prerun_mode)) {
		$rm = $prerun_mode;
        $self->_set_current_runmode($rm);
	}

	# Process run mode!
	my $body = $self->__get_body($rm);

	# Support scalar-ref for body return
	$body = $$body if ref $body eq 'SCALAR';

	# Call cgiapp_postrun() hook
	$self->call_hook('postrun', \$body);

	# Set up HTTP headers
	my $headers = $self->_send_headers();

	# Build up total output
	my $output  = $headers.$body;

	# Send output to browser (unless we're in serious debug mode!)
	print $output unless ($ENV{CGI_APP_RETURN_ONLY});

	# clean up operations
	$self->call_hook('teardown');

	return $output;
}


############################
####  OVERRIDE METHODS  ####
############################

# builder method for query attribute. I'm gonna start with CGI::Simple
sub cgiapp_get_query {
	my $self = shift;

	# Include CGI.pm and related modules
	require CGI::Simple;

	# Get the query object
	my $q = CGI::Simple->new();

	return $q;
}

# init hoook
sub cgiapp_init {
	my $self = shift;
	my @args = (@_);

	# Nothing to init, yet!
}


# prerun hook
sub cgiapp_prerun {
	my $self = shift;
	my $rm = shift;

	# Nothing to prerun, yet!
}


sub cgiapp_postrun {
	my $self = shift;
	my $bodyref = shift;

	# Nothing to postrun, yet!
}


sub setup {
	my $self = shift;

    $self->run_modes(
		'start' => 'dump_html',
	);

}


sub teardown {
	my $self = shift;

	# Nothing to shut down, yet!
}




######################################
####  APPLICATION MODULE METHODS  ####
######################################

# add header, preserving previous
sub header_add {
	my $self = shift;
	return $self->_header_props_update(\@_,'add');
}

# add headers, clobbering previous
sub header_set {
	my $self = shift;
	return $self->_header_props_update(\@_,'set');
}

# clobber all previous headers
sub header_props {
	my $self = shift;
	return $self->_header_props_update(\@_,'props');
}

# used by header_props and header_add to update the headers
sub _header_props_update {
	my $self     = shift;
	my $data_ref = shift;
    my ($meth)    = validate_pos( @_,
        {
            type        => SCALAR,
            regex       => qr/^(add|set|props)$/,
            optional    => 1,
            default     => 'add' # add by default
        }, 
    );

	my @data = @$data_ref;

	my $props;

	# If data is provided, set it!
	if (scalar(@data)) {
		warn "header_props called while header_type set to 'none', headers will NOT be sent!"
            if $self->header_type eq 'none';
            
		# Is it a hash, or hash-ref?
        # Make a copy
		if (ref($data[0]) eq 'HASH')     { %$props = %{$data[0]}; }
        # It appears to be a possible hash (even # of elements)
        elsif ((scalar(@data) % 2) == 0) { %$props = @data; }
        # error
        else {
			confess("Odd number of elements passed to header_$meth().  Not a valid hash")
		}

		# merge in new headers, appending new values passed as array refs
		if ( $meth eq 'add' ) {
            
            # iterate through array ref items and save existing values
			for my $key_set_to_aref (grep { ref $props->{$_} eq 'ARRAY'} keys %$props) {
				my $existing_val = $self->_header_props_get($key_set_to_aref); # save the existing val
				next unless defined $existing_val; 
				my @existing_val_array = (ref $existing_val eq 'ARRAY') ? @$existing_val : ($existing_val);
				$props->{$key_set_to_aref} = [ @existing_val_array, @{ $props->{$key_set_to_aref} } ];
			}
			$self->_header_props_set( %$props ); # put new values in with presevered arrays
		}
        elsif ( $meth eq 'set' ) {
            $self->_header_props_set(%$props);
        }
		# Set new headers, clobbering existing values
		elsif ($meth eq 'props' ) {
			$self->_header_props($props);
		}

	}

	# If we've gotten this far, return the value!
	return (%{ $self->_header_props()});
}

###########################
####  PRIVATE METHODS  ####
###########################


sub _send_headers {
	my $self = shift;
	my $q    = $self->query;
	my $type = $self->header_type;

    return
        $type eq 'redirect' ? $q->redirect( %{$self->_header_props} )
      : $type eq 'header'   ? $q->header  ( %{$self->_header_props} )
      : $type eq 'none'     ? ''
      : confess "Invalid header_type '$type'"
}

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

sub add_callback {
    
    # param - self_or_class - class name or instance of class
    # param - hook - name of the hook to add a callback to
    # param - callback - CODEREF to call 
	my ($self_or_class, $hook, $callback) = @_;

	$hook = lc $hook;

	die "no callback provided when calling add_callback" unless $callback;

    my ( $self, $class ) =  ref $self_or_class
                         ? ( $self_or_class, ref $self_or_class )
                         : (undef, $self_or_class);

    	die "Unknown hook ($hook)"
            unless exists $class->_class_callbacks()->{$hook};
                         
    # if $self, add it only to this instance's callback list
	if ( $self ) {
		# Install in object
        $self->_instance_callbacks()->{$hook} = []
            unless $self->_instance_callbacks()->{$hook};
		push @{ $self->_instance_callbacks()->{$hook} }, $callback;
	}
    # add to the class callback
	else {
		# Install in class
		push @{ $class->_class_callbacks()->{$hook}{$class} }, $callback;
	}

}


# install a new hook, registered at the class level always
sub new_hook {
	my ($class, $hook) = @_;
    # install new hook in the class
    $class->_class_callbacks()->{$hook} = {}
        unless exists $class->_class_callbacks()->{$hook};
	return 1;
}



sub call_hook {
	my $self      = shift;
	my $app_class = ref $self || $self;
	my $hook      = lc shift;
	my @args      = @_;

    # check if hook exists
    confess "Unknown hook ($hook)"
        unless exists $app_class->_class_callbacks()->{$hook};

	my %executed_callback;

	# First, run callbacks installed in the object
    my @instance_callbacks =  defined $self->_instance_callbacks()->{$hook}
                           ? @{ $self->_instance_callbacks()->{$hook} }
                           : ()
                           ;
	foreach my $callback ( @instance_callbacks ) {
		next if $executed_callback{$callback};
		eval { $self->$callback(@args); };
		$executed_callback{$callback} = 1;
		die "Error executing object callback in $hook stage: $@" if $@;
	}

	# Next, run callbacks installed in class hierarchy
	# Cache this value as a performance boost
    if ( scalar @{$self->_superclass_cache()} == 0 ) {
        my @cb_classes = ($app_class->meta->class_precedence_list);
        $self->_superclass_cache( \@cb_classes );
    }

	# Get list of classes that the current app inherits from
	foreach my $class (@{ $self->_superclass_cache }) {

		# skip those classes that contain no callbacks
		next unless exists $self->_class_callbacks()->{$hook}{$class};

        my @callbacks
            = @{ $self->_class_callbacks()->{$hook}{$class} };

		# call all of the callbacks in the class
		foreach my $callback (@callbacks) {
			next if $executed_callback{$callback};
			eval { $self->$callback(@args); };
			$executed_callback{$callback} = 1;
			die "Error executing class callback in $hook stage: $@" if $@;
		}
	}

}

sub dump {
	my $c = shift;
	my $output = '';

	# Dump run mode
	my $current_runmode = $c->get_current_runmode();
	$current_runmode = "" unless (defined($current_runmode));
	$output .= "Current Run mode: '$current_runmode'\n";

	# Dump Params
	$output .= "\nQuery Parameters:\n";
	my @params = $c->query->param();
	foreach my $p (sort(@params)) {
		my @data = $c->query->param($p);
		my $data_str = "'".join("', '", @data)."'";
		$output .= "\t$p => $data_str\n";
	}

	# Dump ENV
	$output .= "\nQuery Environment:\n";
	foreach my $ek (sort(keys(%ENV))) {
		$output .= "\t$ek => '".$ENV{$ek}."'\n";
	}

	return $output;
}


sub dump_html {
	my $c   = shift;
	my $query  = $c->query();
	my $output = '';

	# Dump run-mode
	my $current_runmode = $c->get_current_runmode();
	$output .= "<p>Current Run-mode: '<strong>$current_runmode</strong>'</p>\n";

	# Dump Params
	$output .= "<p>Query Parameters:</p>\n";
	$output .= $query->Dump;

	# Dump ENV
	$output .= "<p>Query Environment:</p>\n<ol>\n";
	foreach my $ek ( sort( keys( %ENV ) ) ) {
		$output .= sprintf(
			"<li> %s => '<strong>%s</strong>'</li>\n",
			$query->escapeHTML( $ek ),
			$query->escapeHTML( $ENV{$ek} )
		);
	}
	$output .= "</ol>\n";

	return $output;
}

__PACKAGE__->meta->make_immutable;

no Moose; 1;

__END__

=pod

=head1 NAME

Web::MooseCap - A Moose port of L<CGI::Application> - a framework for building
reusable web-applications

=head1 SYNOPSIS

  # In "WebApp.pm"...
  package WebApp;
  use Moose;
  extends 'Web::MooseCap';

  # override the base setup routine
  override 'setup' => {
	my $self = shift;
	$self->start_mode('mode1');
	$self->mode_param('rm');
	$self->run_modes(
		'mode1' => 'do_stuff',
		'mode2' => 'do_more_stuff',
		'mode3' => 'do_something_else'
	);
  }
  sub do_stuff { ... }
  sub do_more_stuff { ... }
  sub do_something_else { ... }
  1;


  ### In "webapp.cgi"...
  use WebApp;
  my $webapp = WebApp->new();
  $webapp->run();

=head1 INTRODUCTION

Web::MooseCap: -adjective

=over 4

=item 1.

cheerfully optimistic, hopeful, or confident

=item 2.

reddish; ruddy

=item 3.

CGI::Application remixed with Moose

=back

This started as an experiement in Moose and grew out from there.  Having used
L<CGI::Application> (CAP) for quite a few years, I figured it'd be a good way to
learn by rewriting it with Moose.  After talking with a few others, I thought
perhaps I could give it an actual release and see if anyone wants to use/extend
it.

What Web::MooseCap is NOT: a perfect drop-in replacement for CGI::Application.  Half
the fun of writing this was figuring out how to do things a little different
but maintain the familiarity of the CGI::Application workflow.

It's also not lightweight like CGI::Application.  It is using Moose which incurs
some penalties but adds the joys of Moose.

To use this module, you should have more than a passing familiarity with
L<CGI::Application> as I will not bother reproducing all of that POD here.  This
document will mostly note the differences, additions and how you can do other
nifty things.

=head1 DIFFERENCES

How is this different from CGI::Application?

=over 4

=item 1.

the C<forward> and C<redirect> methods are built in. (See 
L<CGI::Application::Plugin::Forward> and L<CGI::Application::Plugin::Redirect> 
modules.)

=item 2.

Added C<stash> (a la Catalyst)

=item 3.

Added built-in L<Template Toolkit|Template> support (C<tt> to process a template
and <tt_options> to give it defaults) with support for the C<stash>.

=item 4.

Added overrideable cgiapp_stash_init (runs every request, after stash is cleared
but before cgiapp_prerun) that allows you to have certain elements auto-inserted
into the stash for every request.  By default, adds the query object
(C<$self->stash(query=>$self->query())>).

=item 5.

Constructor parameters must all be lower case now.  For example, in a cgi
instance script:

  use Web::MooseCapWebApp;
  
  my $app = Web::MooseCapWebApp->new(
      QUERY     => CGI::Simple->new(),
      TMPL_PATH => [qw{
          /base/webapp/templates
          /instance/webapp/templates
      }],
      PARAMS    => {
        param1  => 1,
        param2  => 2,
      },
  );

This means C<QUERY>, C<TMPL_PATH>, C<PARAMS> should be, respectively C<query>,
C<tmpl_path> and C<params>.  There's no need for the uppercase and since I have
the luxury of not being completely backwards compatible, I'm killing it (as well
as the private C<_cap_hash> methods that forced all keys to upper case).

=item 6.

This is a Moose based system.  You should learn Moose.  In particular, this means
you should use moose conventions when overriding/modifying any of the default
overridable methods.  Instead of:

  sub setup {
    # ...
  }
  
you should do:

  override 'setup' => sub {
    #...
  }

I'll discuss this is more detail later.

=item 7.

New hooks, C<tt> and C<stash_init>

=back

=head1 AUTHOR

Dave Doyle, C<< <dave.s.doyle@gmail.com> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-Web::MooseCap@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org>.  I will be notified, and then you'll automatically
be notified of progress on your bug as I make changes.

=head1 ACKNOWLEDGEMENTS

Thanks to Jesse Erlbaum and Mark Stosberg for CGI::Application.  This is based almost completely on adapting their hard work and all the contributors to CGI::Application.  I can take very little credit at all.

The C<forward> method is stolen almost verbatim from Michael Graham's L<CGI::Application::Plugin::Forward> module.

The C<redirect> method is stolen almost verbatim from Cees Hek's L<CGI::Application::Plugin::Redirect> module.

=head1 COPYRIGHT & LICENSE

Copyright 2008 Dave Doyle, All Rights Reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut
