#!/usr/bin/perl

use strict;
# the number of tests is important, because we want to make sure that
# all run modes are actually reached
use Test::More;

plan 'no_plan';

{
    package WebApp;

    use Moose;
    use Test::More;
    extends 'Web::MooseCap';

    override 'setup' => sub {
        my $self = shift;
        $self->header_type('none');
        $self->start_mode('action_one');
        $self->param('hook' => 0);
        $self->add_callback('forward_prerun', \&hooked_method);
        $self->run_modes({
            action_one => 'meth_one',
            action_two => 'meth_two',
            action_not => 'zzzzzzzz',
        });
    };

    sub meth_one {
        my $self = shift;
        is($self->get_current_runmode, 'action_one', '[meth_one] crm: action_one');
        ok(!$self->param('hook'),                    '[meth_one] hook not called yet 1');
        $self->other_method('foo');
        ok(!$self->param('hook'),                    '[meth_one] hook not called yet 2');
        '';
    }
    sub other_method {
        my $self = shift;
        my @params = @_;
        ok(!$self->param('hook'),                    '[other_method] hook not called yet 1');
        ok(eq_array(\@params, ['foo']),              '[other_method] params');
        is($self->get_current_runmode, 'action_one', '[other_method] crm: action_one');
        my $output = $self->forward('action_two', 'bar', 'baz');
        is($self->param('hook'), 'action_two',       '[other_method] hook called');
        $self->param('hook' => 0);
        ok(!$self->param('hook'),                    '[other_method] hook not called yet 2');
        is($output, 'other_runmode_output',  'other_runmode output');
        eval {
            $output = $self->forward('non_existent', 'bar', 'baz');
        };
        ok($@, 'prevented from forwarding to non-existent run mode');
        ok(!$self->param('hook'),                    '[other_method] hook not called yet 3 (after non-existent)');
        eval {
            $output = $self->forward('action_not', 'bar', 'baz');
        };
        ok(!$self->param('hook'),                    '[other_method] hook not called yet 4 (after non-existent)');
        ok($@, 'prevented from forwarding to non-existent run mode method');
        '';
    }
    sub meth_two {
        my $self = shift;
        my @params = @_;
        ok($self->param('hook'),                        '[meth_two] hook called');
        ok(eq_array(\@params, ['bar', 'baz']),          '[meth_two] params');
        is($self->get_current_runmode, 'action_two',    '[meth_two] crm: action_two');
        return 'other_runmode_output';
    }
    sub hooked_method {
        my $self = shift;
        $self->param('hook' => $self->get_current_runmode);
    }


}


WebApp->new->run;



