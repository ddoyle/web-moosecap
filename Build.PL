use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'Sanguine',
    license             => 'perl',
    dist_author         => 'Dave Doyle <dave.s.doyle@gmail.com>',
    dist_version_from   => 'lib/Sanguine.pm',
    build_requires => {
        'Test::More'                => 0,
        'Moose'                     => 0,
        'MooseX::AttributeHelpers'  => 0,
        'MooseX::ClassAttribute'    => 0,
        'metaclass'                 => 0,
        'Class::MOP'                => 0,
        'Clone'                     => 0,
        'Data::Dumper'              => 0,
        'Params::Validate'          => 0,
        'Template'                  => 0,
    },
    add_to_cleanup      => [ 'Sanguine-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
use Moose;
use Moose::Util::TypeConstraints;
use MooseX::AttributeHelpers;
use MooseX::ClassAttribute;

use metaclass;

use Class::MOP;
use Clone qw(clone);
use Data::Dumper;
use Params::Validate qw(SCALAR HASHREF ARRAYREF validate validate_pos);
use Template;