
package TestApp8;

use Moose;
extends 'Web::MooseCap';


override 'setup' => sub {
	my $self = shift;

	# Test array-ref mode
	$self->start_mode('testcgi1_mode');
	$self->run_modes([qw/
		testcgi1_mode
		testcgi2_mode
		testcgi3_mode
	/]);
};


####  Run Mode Methods

sub testcgi1_mode {
	my $self = shift;

	my $output = "Hello World: testcgi1_mode OK";

	return \$output;
}


sub testcgi2_mode {
	my $self = shift;

	my $output = "Hello World: testcgi2_mode OK";

	return \$output;
}


sub testcgi3_mode {
	my $self = shift;

	my $output = "Hello World: testcgi3_mode OK";

	return \$output;
}


1;

