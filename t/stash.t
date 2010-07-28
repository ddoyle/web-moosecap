#!/usr/bin/perl

{
    package TestApp;
    
    use Moose;
    extends 'Web::MooseCap';
    with 'Web::MooseCap::Role::Stash';


    override 'setup' => sub {
        my $self = shift;
    
        $self->start_mode('basic_test');
    
        $self->mode_param('test_rm');
    
        $self->run_modes(
            'basic_test' => 'basic_test',
        );
    
        $self->param('last_orm', 'setup');
    };
    
    sub basic_test {
        my $self = shift;
    }
    
    __PACKAGE__->meta->make_immutable(); 1;
}

use strict;
use Test::More;
use CGI;
use Data::Dumper;

my $app = TestApp->new();
$app->query(CGI->new({'test_rm' => 'props_before_redirect_test'}));

can_ok($app, qw/stash stash_clear stash_is_empty stash_delete_key/);

#print Dumper( $app->_stash() );

done_testing();
