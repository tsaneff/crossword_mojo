package ValdSimple;
use warnings;
use strict;

sub new{
    my $class = shift;
    my $rules = shift;
    
    my $self = $rules;
    
    bless $self, $class;
    
    return $self;
}

sub validate{
    my $self = shift;
    my $data = shift;
    foreach my $arg ( @$data ){
        foreach my $rule_sub ( @$self ){
            return 0 unless &{$rule_sub}($arg);
        }
    }
    return 1;
}

1;

__END__


=head1 NAME

ValdSimple - Simple and abstract validation class.

=head1 SYNOPSIS

    use ValdSimple;
    
    ...
    
    my $validator = ValdSimple->new( [sub{ shift =~ /^[1-9][0-9]?$/ }] );
    
    if ( $validator->validate( [$height, $height]) ){
        ...
    }

=head1 DESCRIPTION

Validation is done very simply:

1) You need to create ValdSimple object with passing your validation 'rules'.
   Those rules must be structured as array reference to references of subroutines.

2) Call 'validate' method with array reference, holding the arguments to be tested.
   Returned will be 1 or 0, depending on correctness of tested arguments.

=head1 AUTHOR

Stoyan Tsanev

=head1 COPYRIGHT AND LICENSE

Copyright 2012, Stoyan Tsanev.  All rights reserved.  

This library is free software; you can redistribute it and/or modify it under 
the same terms as Perl itself (L<perlgpl>, L<perlartistic>).

=cut
