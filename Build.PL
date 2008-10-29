use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'Sanguine',
    license             => 'perl',
    dist_author         => 'Dave Doyle <dave.s.doyle@gmail.com>',
    dist_version_from   => 'lib/Sanguine.pm',
    build_requires => {
        'Test::More' => 0,
        
    },
    add_to_cleanup      => [ 'Sanguine-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
