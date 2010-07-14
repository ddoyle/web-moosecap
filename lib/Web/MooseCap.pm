package Web::MooseCap;

use Moose;
use Moose::Util::TypeConstraints;
use MooseX::AttributeHelpers;
use MooseX::ClassAttribute;
use MooseX::MultiInitArg;

use metaclass;

use Class::MOP;
use Clone qw(clone);
use Data::Dumper;
use Params::Validate qw(SCALAR HASHREF ARRAYREF validate validate_pos);
#use Template;

our $VERSION   = '0.01';
our $AUTHORITY = 'cpan:DDOYLE';

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

# The query object, compatible with CGI/CGI::Simple etc
has 'query' => (
    traits      => ['MooseX::MultiInitArg::Trait'],
    is          => 'rw',
    isa         => 'Object',
    lazy        => 1,
    builder     => 'cgiapp_get_query',
    init_args   => [qw/QUERY/],
);

# the name of the error mode
has 'error_mode' => ( is => 'rw',
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
    init_arg    => undef,
);

before 'prerun_mode' => sub {
    my $self = shift;
    confess("prerun_mode() can only be called within cgiapp_prerun()!  Error")
        if $self->__prerun_mode_locked();
    return;
};

#########################################
# PRIVATE ATTRIBUTES

# this is to determine the mode param
has '__mode_param' => (
    is          => 'rw',
    isa         => 'Any',
    default => 'rm',
    init_arg => undef,
);

# cache item to remember callback classes checked so we don't have to do the
# expensive $app_class->meta->class_precedence_list every time
has '__superclass_cache' => (
    is          => 'rw',
    isa         => 'ArrayRef[Str]',
    default     => sub { [] },
    init_arg    => undef,
);


# simple lock for the prerun_mode 
has '__prerun_mode_locked' => (
    is          => 'rw',
    isa         => 'Bool',
    default     => 1,
    init_arg    => undef,
);

# stores/sets the current runmode
has '__current_runmode' => (
    isa         => 'Str',
    reader      => 'get_current_runmode',  # public
    writer      => '_set_current_runmode', # private
    init_arg    => undef,
);

# headers to output for a request
has '__header_props' => (
    traits      => [qw(Hash)],
    is          => 'rw',
    isa         => 'HashRef',
    default     => sub { +{} },
    handles    => {
        __header_props_clear => 'clear',
        __header_props_set   => 'set',
        __header_props_get   => 'get',
    },
);

##############
# callback related attribs

# list of installed callbacks on the instance
has '__instance_callbacks' => (
    is          => 'rw',
    isa         => 'HashRef',
    default     => sub { +{} },
);


# base list of callback hooks for the class
class_has '__class_callbacks' => (
    is          => 'rw',
    isa         => 'HashRef',
    default     => sub { return {
    #    hook name            package         sub
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
    traits      => ['MooseX::MultiInitArg::Trait'],
    is          => 'rw',
    isa         => 'HashRef',
    lazy_build  => 1,
    builder     => 'init_params',
    init_args   => [qw/PARAMS/],
);

sub delete {
    my ($self, $key) = @_;
    return unless defined $key;
    return delete $self->params->{$key};
}

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

#######################
# tt with stash integration

sub merge_into {
    my $self      = shift;
    my $base_hash = shift || {};
    
    confess "must pass a hashref" unless ref $base_hash eq 'HASH';
    
    # if we're given a hashref to start, use it
    if (ref $_[0] eq 'HASH') {
        $base_hash->{$_} = $_[0]->{$_} foreach keys %{$_[0]};
        return $base_hash;
    }
    
    # else it's an even number paramlist
    confess "parameter assignment must be an even numbered list" unless
        ((scalar @_ % 2) == 0 );
    
    my %new = @_;
    while( my ($key, $value) = each %new ) {
        $base_hash->{$key} = $value;
    }
    
    return $base_hash;
    
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
    $self->__mode_param( $mode_param )
        if defined $mode_param
            && (
                    ref $mode_param eq 'CODE'
                 || ref $mode_param eq 'HASH'
                 || length $mode_param
            );
        
    return $self->__mode_param();
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
    $self->__prerun_mode_locked(0);

    # Call PRE-RUN hook, now that we know the run mode
    # This hook can be used to provide run mode specific behaviors
    # before the run mode actually runs.
     $self->call_hook('prerun', $rm);

    # If prerun_mode has been set, use it!
    my $prerun_mode = $self->prerun_mode();
    if (length($prerun_mode)) {
        $rm = $prerun_mode;
        $self->_set_current_runmode($rm);
    }

    # Lock prerun_mode from being changed after cgiapp_prerun()
    $self->__prerun_mode_locked(1);

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
    
    # default to utf-8
    $q->charset('utf-8');

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
    return $self->__header_props_update(\@_,'add');
}

# add headers, clobbering previous
sub header_set {
    my $self = shift;
    return $self->__header_props_update(\@_,'set');
}

# clobber all previous headers
sub header_props {
    my $self = shift;
    return $self->__header_props_update(\@_,'props');
}

# used by header_props and header_add to update the headers
sub __header_props_update {
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
                my $existing_val = $self->__header_props_get($key_set_to_aref); # save the existing val
                next unless defined $existing_val; 
                my @existing_val_array = (ref $existing_val eq 'ARRAY') ? @$existing_val : ($existing_val);
                $props->{$key_set_to_aref} = [ @existing_val_array, @{ $props->{$key_set_to_aref} } ];
            }
            $self->__header_props_set( %$props ); # put new values in with presevered arrays
        }
        elsif ( $meth eq 'set' ) {
            $self->__header_props_set(%$props);
        }
        # Set new headers, clobbering existing values
        elsif ($meth eq 'props' ) {
            $self->__header_props($props);
        }

    }

    # If we've gotten this far, return the value!
    return (%{ $self->__header_props()});
}

###########################
####  PRIVATE METHODS  ####
###########################


sub _send_headers {
    my $self = shift;
    my $q    = $self->query;
    my $type = $self->header_type;

    return
        $type eq 'redirect' ? $q->redirect( %{$self->__header_props} )
      : $type eq 'header'   ? $q->header  ( %{$self->__header_props} )
      : $type eq 'none'     ? ''
      : confess "Invalid header_type '$type'"
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

    # can't add a callback unless it exists as a class callback
    # via new_hook or in the default set
    die "Unknown hook ($hook)"
        unless exists $class->__class_callbacks()->{$hook};
                         
    # if $self, add it only to this instance's callback list
    if ( $self ) {
        # Install in object
        $self->__instance_callbacks()->{$hook} = []
            unless $self->__instance_callbacks()->{$hook};
        push @{ $self->__instance_callbacks()->{$hook} }, $callback;
    }
    # add to the class callback
    else {
        # Install in class
        push @{ $class->__class_callbacks()->{$hook}{$class} }, $callback;
    }

}


# install a new hook, registered at the class level always
sub new_hook {
    my ($class, $hook) = @_;
    # install new hook in the class
    $class->__class_callbacks()->{$hook} = {}
        unless exists $class->__class_callbacks()->{$hook};
    return 1;
}



sub call_hook {
    my $self      = shift;
    my $app_class = ref $self || $self;
    my $hook      = lc shift;
    my @args      = @_;

    # check if hook exists
    confess "Unknown hook ($hook)"
        unless exists $app_class->__class_callbacks()->{$hook};

    my %executed_callback;

    # First, run callbacks installed in the object
    my @instance_callbacks =  defined $self->__instance_callbacks()->{$hook}
                           ? @{ $self->__instance_callbacks()->{$hook} }
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
    if ( scalar @{$self->__superclass_cache()} == 0 ) {
        my @cb_classes = ($app_class->meta->class_precedence_list);
        $self->__superclass_cache( \@cb_classes );
    }

    # Get list of classes that the current app inherits from
    foreach my $class (@{ $self->__superclass_cache }) {

        # skip those classes that contain no callbacks
        next unless exists $self->__class_callbacks()->{$hook}{$class};

        my @callbacks
            = @{ $self->__class_callbacks()->{$hook}{$class} };

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

__PACKAGE__->meta->make_immutable; no Moose; 1;

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

It's in Moose. Bigger overhead, yes.  Basically, not a good idea to run as 
vanilla CGI. FastCGI or mod_perl is the way to go.

=item 2.

The C<forward> and C<redirect> methods are built in. (See 
L<CGI::Application::Plugin::Forward> and L<CGI::Application::Plugin::Redirect> 
modules.)

=item 3.

Added built-in L<Template Toolkit|Template> support (C<tt> to process a template
and <tt_options> to give it defaults) with support for the C<stash>.

=item 4.

Added overrideable cgiapp_stash_init (runs every request, after stash is cleared
but before cgiapp_prerun) that allows you to have certain elements auto-inserted
into the stash for every request.  By default, adds the query object
(C<$self->stash(query=>$self->query())>).

=item 5.

Constructor parameters may be upper OR lower case.  For example, in a cgi
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
