use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'Web::MooseCap',
    license             => 'perl',
    dist_author         => 'Dave Doyle <dave.s.doyle@gmail.com>',
    dist_version_from   => 'lib/Web/MooseCap.pm',
    requires => {
        'Moose'                     => 0,
        'MooseX::AttributeHelpers'  => 0,
        'MooseX::ClassAttribute'    => 0,
        'MooseX::MultiInitArg'      => 0,
        'metaclass'                 => 0,
        'Class::MOP'                => 0,
        'Clone'                     => 0,
        'Data::Dumper'              => 0,
        'Params::Validate'          => 0,
        'Template'                  => 0,
        'Test::More'                => 0.47,
    },
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
