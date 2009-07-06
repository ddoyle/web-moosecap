
package TestApp4;

use Moose;
extends 'Web::MooseCap';


override 'setup' => sub {
	my $self = shift;

	$self->start_mode('subref_test');

	$self->run_modes(
		'subref_test' => \&subref_test,
		'AUTOLOAD' => \&autoload_meth
	);
};




############################
####  RUN MODE METHODS  ####
############################

sub subref_test {
	my $self = shift;

	my $output = "Hello World: subref_test OK";

	return \$output;
}


sub autoload_meth {
	my $self = shift;
	my $real_rm = shift;

	return "Hello World: $real_rm OK";
}


__PACKAGE__->meta->make_immutable; no Moose; 1;

