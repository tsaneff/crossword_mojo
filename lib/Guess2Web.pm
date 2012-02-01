package Guess2Web;
use warnings;
use strict;

sub new{
    my $class       = shift;
    my $constraints = shift;
    
    my $self = {};
    
    # Defaults:
    if (not defined $constraints){
        $constraints->{max_len} = 2; # Maximum Guess display digits.
        $constraints->{colors}  = [
            '#90EE90', # LightGreen
            '#AFEEEE', # PaleTurquoise
            '#FFDAB9', # PeachPuff
            '#4682B4', # SteelBlue
            '#D3D3D3', # LightGrey
            '#E0FFFF', # LightCyan
            '#F0E68C', # Khaki
            '#F5DEB3', # Wheat
            '#9ACD32', # YellowGreen
            '#C0C0C0', # Silver
            '#B0E0E6', # PowderBlue
            '#3CB371', # MediumSeaGreen
            '#778899', # LightSlateGrey
            '#8FBC8F', # DarkSeaGreen
            '#E9967A', # DarkSalmon
            '#7FFF00'  # Chartreuse
        ]; # Colors to be used each time 'max_len' constraint is excessed.
    }

    $self = $constraints;
    bless $self, $class;
    
    return $self;
}

sub conv_guess2colorseq{ # Be careful original array reference will be modified!
    my $self = shift;
    my $ar_r = shift;
    
    my $max = 9 x $self->{max_len};
    my $colormap = [ ('') x scalar @$ar_r ];
    
    my $seq = 0;
    my $color_i = 0;
    my $max_color_i = @{$self->{colors}};
    for ( my $i; $i < @$ar_r; ++$i ){
        next if $ar_r->[$i] ne '#';
        
        if ( $seq == $max ){
            $color_i = ( $color_i < $max_color_i ) ? $color_i+1 : 0;
            $seq = 0;
        }
        
        $ar_r->[$i]     = ++$seq;
        $colormap->[$i] = $self->{colors}->[$color_i];
    }
    return $colormap;
}

1;

__END__

=head1 NAME

Guess2Web - The idea is text representation of Crossword::Guess
object to be converted into special id. This id is formed from
the following 2 elements:
1) sequence with fixed length;
2) color

Combination of sequence plus color can be used when displaying
Guess object via CSS and HTML.

=head1 SYNOPSIS

    use Guess2Web;
    
    my $g2w = Guess2Web->new();
    
    # or:  my $g2w = Guess2Web->new({
    #         max_len => 2,
    #         colors  => [ '#90EE90', '#7FFF00' ]
    #      });
    ...
    
    my $cw_control  = $self->crossword->getGrid->getAsFlatArrayRef;
    my $cw_colormap = $g2w->conv_guess2colorseq($cw_control); 
    
=head1 DESCRIPTION

In the example above it is obvious that color information is returned as
array reference. But you must be very careful when using 'conv_guess2colorseq'
subroutine, because Guess objects data ('#') within passed array reference
will be converted into fixed sequence number, i.e. passed array reference
will be modified!

=head1 AUTHOR

Stoyan Tsanev

=head1 COPYRIGHT AND LICENSE

Copyright 2012, Stoyan Tsanev.  All rights reserved.  

This library is free software; you can redistribute it and/or modify it under 
the same terms as Perl itself (L<perlgpl>, L<perlartistic>).

=cut
