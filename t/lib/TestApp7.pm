package TestApp7;

use Moose;
extends 'Web::MooseCap';
use CGI::Carp;


after 'setup' => sub {
	my $self = shift;

	$self->run_modes(
		testcgi_mode => 'testcgi_mode'
	);
};


sub cgiapp_get_query  {
	my $self = shift;

	require TestCGI;
	my $q = TestCGI->new();

	return $q;
}


####  Run Mode Methods

sub testcgi_mode {
	my $self = shift;

	my $output = "Hello World: testcgi_mode OK";

	return \$output;
}


__PACKAGE__->meta->make_immutable; no Moose; 1;

