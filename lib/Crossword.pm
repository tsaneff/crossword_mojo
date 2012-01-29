package Crossword;
use utf8;
use DBI;
use Carp;
use warnings;
use strict;

# Debugging:
use constant DEBUG                    => 1;
use constant PRINT_STDOUT             => 0;
use constant LOG_FILE                 => 'crossword_gen.log';
use Data::Dumper;

# Benchmark:
use constant BENCHMARK                => 0;
use Benchmark::Timer;

# Db:
use constant TXT_DB_MODE              => 0;
use constant WORDS_TXT_DB_FILE        => 'db/BGN.words.dat'; 
use constant DESCRIPTIONS_TXT_DB_FILE => 'db/BGN.descriptions.dat';
use constant DB_CONN                  => 'DBI:mysql:crossword_proj';
use constant DB_USER                  => 'uzer';
use constant DB_PASS                  => 'pazz';

sub new{
    my $class = shift;
    my $data  = shift;
    
    # Validate input args:
    Crossword::Toolz::vald_args( $data, [ qw{ width height} ]);
    
    my $self = {
        grid      => Crossword::Grid->new({ width => $data->{width}, height => $data->{height} }),
        guessList => ''
    };
    
    bless $self, $class;
    return $self;
}

sub fill{
    my $self = shift;
    my $data = shift;
    
    Crossword::Toolz::vald_args( $data, [ qw{ algorithm } ] );
    
    my $alg = Crossword::Algorithm->new( { type => $data->{algorithm} } );
    
    my $timer;
    if ( BENCHMARK ){
        $timer = Benchmark::Timer->new();
        $timer->start();
    }
    
    if ( DEBUG ){
        open LOG, '>:utf8', LOG_FILE or confess $!;
    }
    
    logger (sub{ print LOG "Starting crossword generation process with algorithm: $data->{algorithm}\n"; });
    
    my ( $dbh, $sth_words, $sth_desc ) = ( '' ) x 3;
    if ( not TXT_DB_MODE ){
        
        # Establishing DB connection:
        $dbh = DBI->connect( DB_CONN, DB_USER, DB_PASS ) 
            or confess "Couldn't connect to database: ".DBI->errstr;
        
        # MySQL utf8 data retrieving hacks:
        $dbh->{'mysql_enable_utf8'} = 1;
        $dbh->do('SET NAMES utf8');
        
        # Prepare statements:
        $sth_words     = $dbh->prepare( 'SELECT id, word FROM words WHERE word_len = ? and word RLIKE ?' )
            or confess "Couldn't prepare statement: ".$dbh->errstr;
        
        $sth_desc      = $dbh->prepare( 'SELECT description FROM descriptions WHERE word_id = ?' )
            or confess "Couldn't prepare statement: ".$dbh->errstr;
    }
    
    my $grid               = $self->{grid};
    my $MAX_WORD_LEN       = queryMaxWordLen($dbh);
    my $duplicateProtector = Crossword::DuplicateProtector->new();
    
    ##################################################
    # Set outer words:                               #
    ##################################################
    
    $grid->placeBorderWords(
        {
            init_step           => 1,
            offset              => 0,
            word_placement      => 'corner',
            max_word_len        => $MAX_WORD_LEN,
            duplicate_protector => $duplicateProtector,
            sth_words           => $sth_words,
            sth_desc            => $sth_desc
        }
    );
    
    ############################
    # Fill not completed lines #
    ############################
    
    $grid->fillWhileEndsExists( 
        { 
            max_word_len        => $MAX_WORD_LEN,
            duplicate_protector => $duplicateProtector,
            sth_words           => $sth_words,
            sth_desc            => $sth_desc
        }
    );
    
    if ($alg->{isUsingTraces}){

        ############################################################
        # Limit 'uncrossable' word chances by adding 'word traces' #
        ############################################################

        $grid->setTracesByX( 
            { 
                max_word_len        => $MAX_WORD_LEN,
                duplicate_protector => $duplicateProtector,
                sth_words           => $sth_words,
                sth_desc            => $sth_desc
            }
        );
    }
    
    if ($alg->{isGreedy}){
        #################################
        # Fill Guesses of type 'nextTo' #
        #################################
        
        $grid->placeBorderWords(
            {
                init_step           => 2,
                offset              => 1,
                word_placement      => 'nextTo',
                max_word_len        => $MAX_WORD_LEN,
                duplicate_protector => $duplicateProtector,
                sth_words           => $sth_words,
                sth_desc            => $sth_desc
            }
        );
        
        ############################
        # Fill not completed lines #
        ############################
        
        $grid->fillWhileEndsExists( 
            { 
                max_word_len        => $MAX_WORD_LEN,
                duplicate_protector => $duplicateProtector,
                sth_words           => $sth_words,
                sth_desc            => $sth_desc
            }
        );
        
        ############################
    }
    
    ###############################################
    # Place 'Graves' over all non-Letter objects  #
    ###############################################

    $grid->placeDaGraves();
    
    ###############################################
    
    logger (sub{ print LOG Dumper(\$grid); });
    logger (sub{ $grid->displayTxtGrid(*LOG) });
 
    #############################
    # FILL GUESSLIST            #
    #############################
    
    $self->{guessList} = $grid->scan4objects(
        { types => ['Crossword::Grid::Guess'], rule => sub{return 1} }
    ); # IMPL: $self->{guessList} is better 2 B Guess obj's ref than hash with Guess obj's coords!
    
    #############################
    $self->displayTxtGuessListPane(*LOG);
    
    if ( BENCHMARK ){
        $timer->stop;
        logger (sub{ print LOG 'ELAPSED TIME: ',$timer->result(),"\n"; });
    }
    
    if ( DEBUG ){
        close LOG or confess $!;
    }
}

sub getGrid{
    return shift->{grid};
}

sub getGuessList{
    return shift->{guessList};
}

sub displayTxtGuessListPane{
    my $self    = shift;
    my $handler = shift;
    
    my $grid            = $self->getGrid();
    my $guessListCoords = $self->getGuessList();
    
    my $seq = 0;
    my $guess;
    foreach (@{$guessListCoords}){
        $guess = $grid->[$_->{y}][$_->{x}];
        $seq++;
        print $handler "Guess N$seq:\n";
        foreach my $arrow (sort {$a cmp $b} keys %{$guess->{arrows}}){
            print $handler "\t[arrow: $arrow] description: ".$guess->{arrows}->{$arrow}."\n";
        }
    }
}

sub getWord{
    my $Grid = shift;
    my $data = shift;
    
    Crossword::Toolz::vald_args( $data,
        [ qw{ offset sticked_axis_val direction duplicate_protector 
        max_word_len sth_words sth_desc } ]
    );
    
    $data->{return_type} = 'rand_word';
    
    return getMatchedData($Grid, $data);
}

sub getMatchedData{
    my $Grid = shift;
    my $data = shift;
    
    Crossword::Toolz::vald_args( $data,
        [ qw{ offset sticked_axis_val direction duplicate_protector 
        max_word_len return_type sth_words sth_desc } ]
    );
    
    my $PUZZLE_H = scalar @{$Grid};
    my $PUZZLE_W = scalar @{$Grid->[0]};

    my $axis_max = ($data->{direction} eq 'x' ) ? $PUZZLE_W : $PUZZLE_H;
    my $limit    = ($axis_max >= $data->{max_word_len} + $data->{offset}) ?
        $data->{max_word_len} + $data->{offset} : $axis_max;

    my $words;
    do{
	    $words = queryWords( $Grid->getWordRegex(
			{
				offset           => $data->{offset},
				sticked_axis_val => $data->{sticked_axis_val},
				direction        => $data->{direction},
				limit            => $limit
			}), $data->{sth_words}
	    );
	    @{$words} = grep { not $data->{duplicate_protector}->isUsed($_->{word}) } @{$words};
	    --$limit;
	    
	    if ( PRINT_STDOUT ){
            print 'DIRECTION: '       . $data->{direction} .
                '; sticked_axis: '    . $data->{sticked_axis_val}.
                '; moving_ax_offset: '. $data->{offset}.
                "; LIMIT: $limit\n";
        }
        logger (sub{ 
            print LOG 'DIRECTION: '   . $data->{direction} .
                '; sticked_axis: '    . $data->{sticked_axis_val}.
                '; moving_ax_offset: '. $data->{offset}.
                "; LIMIT: $limit\n";
        });
    } until (@{$words} or $limit == 1);
    
    if ( $data->{return_type} eq 'rand_word' ){
        my $word = {};
        if ( @{$words} ){
            $word = $words->[ rand $#$words ];
            $word->{desc} = queryWordDesc( $word->{id}, $data->{sth_desc} );
        } 
        return $word;
    } elsif ( $data->{return_type} eq 'all_words' ) {
        return $words;
    } else {
        confess "Crossword->getMatchedData(): Wrong 'return_type' argument value [".$data->{return_type}.'] ';
    }
}

sub queryMaxWordLen{ # Inteface!
    (TXT_DB_MODE) ? Crossword::DB::Txt::queryMaxWordLen(@_) : Crossword::DB::Rel::queryMaxWordLen(@_);
}

sub queryWords{ # Inteface!
    (TXT_DB_MODE) ? Crossword::DB::Txt::queryWords(@_) : Crossword::DB::Rel::queryWords(@_);
}

sub queryWordDesc{ # Inteface!
    (TXT_DB_MODE) ? Crossword::DB::Txt::queryWordDesc(@_) : Crossword::DB::Rel::queryWordDesc(@_);
}

sub logger{
    &{(shift)} if DEBUG;
}

package Crossword::Algorithm;
use Carp;
use warnings;
use strict;

sub new{
    my $class = shift;
    my $data  = shift;
    
    Crossword::Toolz::vald_args( $data, [ qw{ type } ] );
    
    my $self = {};
    
    # Algorithm atoms:
    if    ( $data->{type} eq 'FishNet' ){
        $self->{isGreedy}      = 0;
        $self->{isUsingTraces} = 0;
    }
    elsif ( $data->{type} eq 'ChuckNorris' ){
        $self->{isGreedy}      = 1;
        $self->{isUsingTraces} = 0;
    }
    elsif ( $data->{type} eq 'TraceFull' ){
        $self->{isGreedy}      = 1;
        $self->{isUsingTraces} = 1;
    } else {
        confess "Crossword::Algorithm with type [$data->{type}] is not implemented yet, so U R welcome!...";
    }

    bless $self, $class;
    return $self;
}

package Crossword::DuplicateProtector;
use warnings;
use strict;

sub new{
    my $class  = $_[0];
    my $self = {}; # anon. hash. ref. will be used as word stash, holding unique crosswords.
    bless $self, $class;
    return $self;
}

sub isUsed{
    my $self = shift;
    my $word = shift;
    return (defined $self->{$word}) ? 1 : 0;
}

sub save{
    my $self = shift;
    my $word = shift;
    if ( $self->isUsed($word) ){
        return 0;
    } else {
        $self->{$word} = 1;
        return 1;
    }
}

package Crossword::Grid;
use Carp;
use warnings;
use strict;

sub new{
    my $class = shift;
    my $data  = shift;
    
    Crossword::Toolz::vald_args( $data, [ qw{ width height } ]);
    
    my ( $PUZZLE_W, $PUZZLE_H ) = ( $data->{width}, $data->{height} );
    
    # Fill Grid with Filler Objects:
    my $self;
    for (my $y=0; $y < $PUZZLE_H; ++$y){
        for (my $x=0; $x < $PUZZLE_W; ++$x){
            $self->[$y][$x] = Crossword::Grid::Filler->new();
        }
    }
    bless $self, $class;
    return $self;
}

sub placeBorderWords{
    my $self = shift;
    my $data = shift;
    
    Crossword::Toolz::vald_args( 
        $data, [ qw{ init_step offset word_placement duplicate_protector max_word_len sth_words sth_desc } ]
    );
    
    my $PUZZLE_W           = scalar @{$self->[0]};
    my $PUZZLE_H           = scalar @{$self};
    my $MAX_WORD_LEN       = $data->{max_word_len};
    my $duplicateProtector = $data->{duplicate_protector};
    my $offset             = $data->{offset};
    my $word_placement     = $data->{word_placement};
    my $sth_words          = $data->{sth_words};
    my $sth_desc           = $data->{sth_desc};
    
    Crossword::logger (sub{ print Crossword::LOG "placeBorderWords(): Try to place grid outer objects...\n"; });
    
    my ($x, $y) = ($data->{init_step}) x 2;
    do{
        # SET WORD BY 'Y' AXIS:
        if ($x < $PUZZLE_W){ # Because our grid can be rectanglar!
            my $args = {
                offset              => $offset,
                sticked_axis_val    => $x,
                direction           => 'y',
                duplicate_protector => $duplicateProtector,
                max_word_len        => $MAX_WORD_LEN,
                sth_words           => $sth_words,
                sth_desc            => $sth_desc
            };
            $args->{word_data}      = Crossword::getWord( $self, $args );
            $args->{word_placement} = $word_placement;
            $self->placeObjects( $args );
        }

        # SET WORD BY 'X' AXIS:
        if ($y < $PUZZLE_H){ # Because our grid can be rectanglar!
            my $args = {
                offset              => $offset,
                sticked_axis_val    => $y,
                direction           => 'x',
                duplicate_protector => $duplicateProtector,
                max_word_len        => $MAX_WORD_LEN,
                sth_words           => $sth_words,
                sth_desc            => $sth_desc
            };
            $args->{word_data}      = Crossword::getWord( $self, $args );
            $args->{word_placement} = $word_placement;
            $self->placeObjects( $args );
        }
        $x+=2;
        $y+=2;
    } until ($x > $PUZZLE_W && $y > $PUZZLE_H);
    
    Crossword::logger (sub{ print Crossword::LOG "placeInitWordss(): Returning...\n"; });
}

sub fillWhileEndsExists{
    my $self = shift;
    my $data = shift;
    
    Crossword::Toolz::vald_args( 
        $data, [ qw{ duplicate_protector max_word_len sth_words sth_desc } ]
    );
    
    my $PUZZLE_W           = scalar @{$self->[0]};
    my $PUZZLE_H           = scalar @{$self};
    my $MAX_WORD_LEN       = $data->{max_word_len};
    my $duplicateProtector = $data->{duplicate_protector};
    my $sth_words          = $data->{sth_words};
    my $sth_desc           = $data->{sth_desc};
    
    Crossword::logger (sub{ print Crossword::LOG "fillWhileEndsExists(): Try to fill not one-word-only lines...\n"; });
    
    my @ends;
    my $end_coords;
    
    # SET WORDS BY 'X' AXIS:
    while ( (@ends = @{$self->scan4ends('x')}) > 0 ){
        foreach $end_coords ( @ends ){
            if ($end_coords->{x}+1 == $PUZZLE_W){
                if ($self->[$end_coords->{y}][$end_coords->{x}]->getDirection() !~ /\[xy\]|\[yx\]/){
                    $self->[$end_coords->{y}][$end_coords->{x}]->setDirection('y');
                } else {
                    $self->placeGrave( { x => $end_coords->{x}, y => $end_coords->{y}} );
                }
                next;
            } elsif ($end_coords->{y} < $PUZZLE_H){
                my $args = {
                    offset              => $end_coords->{x}+1,
                    sticked_axis_val    => $end_coords->{y},
                    direction           => 'x',
                    duplicate_protector => $duplicateProtector,
                    max_word_len        => $MAX_WORD_LEN,
                    sth_words           => $sth_words,
                    sth_desc            => $sth_desc
                };
                $args->{word_data}      = Crossword::getWord($self,$args);
                $args->{word_placement} = 'nextTo';
                $self->placeObjects($args);
            }
        }
    }

    # SET WORDS BY 'Y' AXIS:
    while ( (@ends = @{$self->scan4ends('y')}) > 0 ){
        foreach $end_coords ( @ends ){
            if ($end_coords->{y}+1 == $PUZZLE_H){
                if ($self->[$end_coords->{y}][$end_coords->{x}]->getDirection() !~ /\[xy\]|\[yx\]/){
                    $self->[$end_coords->{y}][$end_coords->{x}]->setDirection('x');
                } else {
                    $self->placeGrave( { x => $end_coords->{x}, y => $end_coords->{y}} );
                }
                next;
            } elsif ($end_coords->{x} < $PUZZLE_W){
                my $args = {
                    offset              => $end_coords->{y}+1,
                    sticked_axis_val    => $end_coords->{x},
                    direction           => 'y',
                    duplicate_protector => $duplicateProtector,
                    max_word_len        => $MAX_WORD_LEN,
                    sth_words           => $sth_words,
                    sth_desc            => $sth_desc
                };
                $args->{word_data}      = Crossword::getWord($self,$args);
                $args->{word_placement} = 'nextTo';
                $self->placeObjects($args);
            }
        }
    }
    Crossword::logger (sub{ print Crossword::LOG "fillWhileEndsExists(): Returning ...\n"; });
}

sub setTracesByX{
    my $self = shift;
    my $data = shift;
    
    Crossword::Toolz::vald_args( 
        $data, [ qw{ duplicate_protector max_word_len sth_words sth_desc } ]
    );
    
    my $PUZZLE_H           = scalar @{$self};
    my $MAX_WORD_LEN       = $data->{max_word_len};
    my $duplicateProtector = $data->{duplicate_protector};
    my $sth_words          = $data->{sth_words};
    my $sth_desc           = $data->{sth_desc};
    
    # SET TRACES BY X AXIS:
    for (my $y = 2; $y < $PUZZLE_H; $y+=2){
        my $args = {
            offset              => 1,
            sticked_axis_val    => $y,
            direction           => 'x',
            duplicate_protector => $duplicateProtector,
            max_word_len        => $MAX_WORD_LEN,
            return_type         => 'all_words',
            sth_words           => $sth_words,
            sth_desc            => $sth_desc 
        };
        $args->{word_data}      = Crossword::getMatchedData( $self, $args );
        $args->{word_placement} = 'nextTo';
        $self->setTraces($args);
    }
}

sub placeObjects{
	my $Grid = $_[0]; # get "self" (object) reference!
    my $data = $_[1];
    
    Crossword::Toolz::vald_args( 
        $data, [ qw{ word_data offset sticked_axis_val direction duplicate_protector word_placement} ]
    );
    
    # Depending on placing direction "moving" and "sticked" axis needs 2 B determinated:
    my ($sticked_ax, $moving_ax) = ( $data->{sticked_axis_val}, $data->{offset} );
    my ($w_sticked_offset, $w_moving_offset);
    
    my ($guX, $guY, $woX, $woY, $grX, $grY);
    if    ($data->{word_placement} eq 'corner'){
		($w_sticked_offset, $w_moving_offset) = (-1, 0); ($grX, $grY) = (\$woX, \$woY) }
	elsif ($data->{word_placement} eq 'nextTo'){ 
		($w_sticked_offset, $w_moving_offset) = ( 0,-1); ($grX, $grY) = (\$guX, \$guY) }
	else {
		confess "Grid->placeObjects() called with wrong 'word_placement' argument value".$data->{word_placement};
	}
    
    if ($data->{direction} eq 'x'){
        ($woX, $woY) = ($moving_ax,                      $sticked_ax                    );
		($guX, $guY) = ($moving_ax  + $w_moving_offset,  $sticked_ax + $w_sticked_offset);
    } else {
        ($woX, $woY) = ($sticked_ax,                     $moving_ax                   );
		($guX, $guY) = ($sticked_ax + $w_sticked_offset, $moving_ax + $w_moving_offset);
    }

	if ( defined $data->{word_data}->{word} ){
        Crossword::logger (sub{ print Crossword::LOG "Word 2 B placed @ x=",$woX,", y=",$woY,": ", $data->{word_data}->{word},"\n"; });
        $data->{duplicate_protector}->save( $data->{word_data}->{word} );
        $Grid->placeGuess( 
            { 
                x => $guX, y => $guY, wordDescription => $data->{word_data}->{desc}, 
                arrow => $data->{word_placement}.$data->{direction}
            }
        );
        $Grid->placeWord(
            {
                x => $woX, y => $woY, direction => $data->{direction}, 
                wordData => $data->{word_data}->{word} 
            }
        );
        Crossword::logger (sub{ $Grid->displayTxtGrid(*Crossword::LOG) });
	} else {
	    if ( ref $Grid->[$$grY][$$grX] ne 'Crossword::Grid::Guess'){
            $Grid->placeGrave( { x => $$grX, y => $$grY } );
             Crossword::logger (sub{ print Crossword::LOG "Grave placed @ x => ",$$grX," y =>", $$grY,"\n"; });
        } else {
            Crossword::logger (sub{ print Crossword::LOG "Grave banned @ x=",$$grX,", y=",$$grY,"\n"; });
        }
	}
}

sub setTraces{
	my $Grid = $_[0]; # get "self" (object) reference!
    my $data = $_[1];
    
    Crossword::Toolz::vald_args( 
        $data, [ qw{ word_data offset sticked_axis_val direction duplicate_protector word_placement} ]
    );
    
    # Depending on placing direction "moving" and "sticked" axis needs 2 B determinated:
    my ($sticked_ax, $moving_ax) = ( $data->{sticked_axis_val}, $data->{offset} );
    my ($w_sticked_offset, $w_moving_offset);
    
    my ($guX, $guY, $woX, $woY, $grX, $grY);
    if    ($data->{word_placement} eq 'corner'){
		($w_sticked_offset, $w_moving_offset) = (-1, 0); ($grX, $grY) = (\$woX, \$woY) }
	elsif ($data->{word_placement} eq 'nextTo'){ 
		($w_sticked_offset, $w_moving_offset) = ( 0,-1); ($grX, $grY) = (\$guX, \$guY) }
	else {
		confess "Grid->placeObjects() called with wrong 'word_placement' argument value [".$data->{word_placement}.'] ';
	}
    
    if ($data->{direction} eq 'x'){
        ($woX, $woY) = ($moving_ax,                      $sticked_ax                    );
		($guX, $guY) = ($moving_ax  + $w_moving_offset,  $sticked_ax + $w_sticked_offset);
    } else {
        ($woX, $woY) = ($sticked_ax,                     $moving_ax                   );
		($guX, $guY) = ($sticked_ax + $w_sticked_offset, $moving_ax + $w_moving_offset);
    }

	if ( defined $data->{word_data} ){
        foreach my $word ( @{$data->{word_data}} ){
            Crossword::logger (sub{ 
                print Crossword::LOG "Trace 2 B placed @ x=", $woX,
                    ", y=", $woY, ": ", $word->{word}, "\n";
            });
            $Grid->placeTrace(
                {
                    x => $woX, y => $woY, direction => $data->{direction}, 
                    wordData => $word->{word}
                }
            );
        }
        Crossword::logger (sub{ $Grid->displayTxtGrid(*Crossword::LOG) });
	}
}

sub placeTrace{
    my $Grid      = $_[0]; # get "self" (object) reference!
    my $data      = $_[1];
    
    Crossword::Toolz::vald_args( $data, [ qw{ x y direction wordData} ]);
        
    my @word = split //, $data->{wordData};
    Crossword::logger (sub{ print Crossword::LOG "Trace 2 B placed: ",join '|', @word,"\n"; });
    my ($x, $y, $direction) = ($data->{x}, $data->{y}, $data->{direction});
    foreach my $letter (@word){
        $Grid->[$y][$x]->updateRegex($letter) if ref $Grid->[$y][$x] eq 'Crossword::Grid::Filler';
        ($data->{direction} eq 'x') ? ++$x : ++$y;
    }
}

sub placeWord{
    my $Grid      = $_[0]; # get "self" (object) reference!
    my $data      = $_[1];
    
    my $PUZZLE_H = scalar @{$Grid};
    my $PUZZLE_W = scalar @{$Grid->[0]};
    
    Crossword::Toolz::vald_args( $data, [ qw{ x y direction wordData} ]);
        
    my @word = split '', $data->{wordData};
    my ($x, $y, $direction) = ($data->{x}, $data->{y}, $data->{direction});
    foreach my $letter (@word){
        $Grid->[$y][$x++] = Crossword::Grid::Letter->new($letter) if $data->{direction} eq 'x';
        $Grid->[$y++][$x] = Crossword::Grid::Letter->new($letter) if $data->{direction} eq 'y';
    }
    $Grid->placeEnd({x => $x, y => $y, direction => $direction}) if $y < $PUZZLE_H && $x < $PUZZLE_W;
}

sub placeEnd{
    my $Grid = $_[0]; # get "self" (object) reference!
    my $data = $_[1];

    Crossword::Toolz::vald_args( $data, [ qw{ x y direction } ]);    
    
    my ($x, $y, $direction) = ($data->{x}, $data->{y}, $data->{direction});
    # If end is already defined on this position, only it's direction is updated:
    if (ref $Grid->[$y][$x] eq 'Crossword::Grid::End'){
        $Grid->[$y][$x]->setDirection('[xy]');
    } else {
        $Grid->[$y][$x] = Crossword::Grid::End->new($direction) if
            ref $Grid->[$y][$x] ne 'Crossword::Grid::Guess' and 
            ref $Grid->[$y][$x] ne 'Crossword::Grid::Grave';
    }
}

sub placeGrave{
    my $Grid = $_[0]; # get "self" (object) reference!
    my $data = $_[1];
    
    Crossword::Toolz::vald_args( $data, [ qw{ x y } ]);
    
    my ($x, $y) = ($data->{x}, $data->{y});
    $Grid->[$y][$x] = Crossword::Grid::Grave->new();
}

sub placeGuess{
    my $Grid = $_[0]; # get "self" (object) reference!
    my $data = $_[1];
    
    Crossword::Toolz::vald_args( $data, [ qw{ x y wordDescription arrow } ]);

    my ($x, $y) = ($data->{x}, $data->{y});
    
    if (ref $Grid->[$y][$x] ne 'Crossword::Grid::Guess'){
        $Grid->[$y][$x] = Crossword::Grid::Guess->new(
            { wordDescription => $data->{wordDescription}, arrow => $data->{arrow} }
        );
    } else {
        $Grid->[$y][$x]->append(
            { wordDescription => $data->{wordDescription}, arrow => $data->{arrow} }
        );
    }
}

sub getWordRegex{
    my $Grid = $_[0]; # get "self" (object) reference!
    my $data = $_[1];
    
    Crossword::Toolz::vald_args( $data, [ qw{ offset sticked_axis_val direction limit } ]);
    
    # Depending on scan direction "moving" and "sticked" axis needs to be determinated:
    my ( $sticked_ax, $moving_ax ) = ( $data->{sticked_axis_val}, $data->{limit} );
    my ( $x, $y, $mv_ax_size ) = ( $data->{direction} eq 'x' ) ?
        ( \$moving_ax, \$sticked_ax, scalar @{$Grid->[0]}) : ( \$sticked_ax, \$moving_ax, scalar @{$Grid});
    
    my $limit = $data->{limit};
    
    # Fix placing word end identifier over part of another word, like the following eg.:
    
                                           #cat#
                                           ####e
                                           ####a (X: cat, Y: tea)
    # NB: Will be fixed also and unwanted cases with placing 'sticking' words like:
                                           #catt
                                           ####e
                                           ####a (X: cat, Y: tea)
    if ($limit < $mv_ax_size){ #  This check exist to protect from cases when $limit is ...
    # ... inicialized with the maxim axis size ( PUZZLE_H / PUZZLE_W or Grid row / column size+1!).
        --$limit until ( ref $Grid->[$$y][$$x] ne 'Crossword::Grid::Letter' or $data->{offset} > $limit );
    }
    
    my $line ='';
    my $len = 0;
    for ($moving_ax = $data->{offset}; $moving_ax < $limit; $moving_ax++){
        last if ref $Grid->[$$y][$$x] eq 'Crossword::Grid::End'   or
                ref $Grid->[$$y][$$x] eq 'Crossword::Grid::Grave' or
                ref $Grid->[$$y][$$x] eq 'Crossword::Grid::Guess';
        $line.= $Grid->[$$y][$$x]->getData();
        ++$len;
    }
    return { len => $len, regex => $line };
}

sub scan4ends{
    my $Grid      = $_[0]; # get "self" (object) reference!
    my $direction = $_[1]; # Allows only 'x' or only 'y' or both type of Ends 2 B returned!
    
    return $Grid->scan4objects(
        {
            types => [ 'Crossword::Grid::End' ],
            rule => sub{
                my $Grid = shift;
                my $y    = shift;
                my $x    = shift;
                return $Grid->[$y][$x]->getDirection() =~ /$direction/;
            }
        }
    );
}

sub scan4objects{ # IMPL: if not used for other objects than Ends and Guess, this f() needs 2 B deprecated!
    my $Grid = shift; # get "self" (object) reference!
    my $data = shift;
    
    Crossword::Toolz::vald_args( $data, [ qw{types rule} ] );
    
    my $types    = $data->{types};
    
    my $PUZZLE_H = scalar @{$Grid};
    my $PUZZLE_W = scalar @{$Grid->[0]};
    
    my $obj_coords = [];
    for (my $y=0; $y < $PUZZLE_H; ++$y){
        for (my $x=0; $x < $PUZZLE_W; ++$x){
            foreach my $type (@{$types}){
                if (ref $Grid->[$y][$x] eq $type and &{$data->{rule}}($Grid, $y, $x)){
                    push @{$obj_coords}, { y => $y, x => $x };
                }
            }
        }
    }
    return $obj_coords;
}

sub displayTxtGrid{
    my $Grid    = $_[0]; # get "self" (object) reference!
    my $handler = $_[1];
    
    my $PUZZLE_H = scalar @{$Grid};
    my $PUZZLE_W = scalar @{$Grid->[0]};
    
    for (my $y=0; $y < $PUZZLE_H; ++$y){
        for (my $x=0; $x < $PUZZLE_W; ++$x){

            # Detailed print: printf $handler "% 3.3s", $Grid->[$y][$x]->getData();
            if ($Grid->[$y][$x]->getData() eq '\w' or $Grid->[$y][$x]->getData() eq '..'){
                print $handler '* ';
            } elsif (ref $Grid->[$y][$x] eq 'Crossword::Grid::Filler'){
                print $handler '~ ';
            } else {
                print $handler $Grid->[$y][$x]->getData().' ';
            }
        }
        print $handler "\n";
    }
}

sub placeDaGraves{
    my $self = shift;
    
    my $PUZZLE_H = scalar @{$self};
    my $PUZZLE_W = scalar @{$self->[0]};
    
    for (my $y=0; $y < $PUZZLE_H; ++$y){
        for (my $x=0; $x < $PUZZLE_W; ++$x){
            if ( ref $self->[$y][$x] ne 'Crossword::Grid::Letter' and 
                 ref $self->[$y][$x] ne 'Crossword::Grid::Guess' ){
                $self->[$y][$x] = Crossword::Grid::Grave->new();
            }
        }
    }
}

package Crossword::Grid::Filler;
# "Crossword::Grid::Filler" will be used in order to mark Crossword's areas where no letter is placed!
use warnings;
use strict;
use constant TXT_DB_MODE => &Crossword::TXT_DB_MODE;

sub new{
    my $class = $_[0];
    
    my $match_all = ( TXT_DB_MODE ) ? '\w' : '..'; # hack: As MySQL regex op's are byte dependant, ...
    # ... because of 2 byte length of UTF-8, '.' op is applied 2 times!
   
    my $self = { $match_all => 1 }; 
    bless $self, $class;
    return $self;
}

sub updateRegex{
    my $self   = shift;
    my $letter = shift;
    
    Crossword::logger (sub{ print Crossword::LOG "DEBUG: updateRegex() letter = ",$letter,"\n"; });
    
    my $match_all = ( TXT_DB_MODE ) ? '\w' : '..';
    if ( defined $self->{$match_all} ){
        delete $self->{$match_all};
    }
    $self->{$letter} = 1;
}

sub getData{
    my $self = shift;
    
    if (scalar keys %{$self} == 1){
        return (keys %{$self})[0];
    } else {
        my ( $grop_l, $delim, $grop_r ) = ( TXT_DB_MODE ) ? ( '[' , '' , ']' ) : ( '(' , '|' , ')' );
        return $grop_l. ( join $delim, keys %{$self} ). $grop_r;
    }
}

package Crossword::Grid::End;
# "Crossword::Grid::End" will be used in order to mark word ends!
# Also only over "End" could be placed "Guess" (except when placing outer words at the begining...)!
use Carp;
use warnings;
use strict;

use constant END_IDENTIFIER => '$';

sub new{
    my $class     = $_[0];
    my $direction = $_[1];
    
    my $self = {
        cellData  => END_IDENTIFIER,
        direction => $direction
    };
    bless $self, $class;
    return $self;
}

sub getData{
    return shift->{cellData};
}

sub getDirection{
    return shift->{direction};
}

sub setDirection{
    my $self      = shift;
    my $direction = shift;
    confess "Wrong value [$direction] for Object End's method 'direction'"
        unless $direction =~ /x|y|\[xy\]|\[yx\]/;
    $self->{direction} = $direction;
}

package Crossword::Grid::Grave;
# "Crossword::Grid::Grave" will be used in order to mark places where no letter could be placed!
use warnings;
use strict;
use constant GRAVE_IDENTIFIER => '%';

sub new{
    my $class = $_[0];
    my $cellData = GRAVE_IDENTIFIER;
    my $self = \$cellData; # ref to scalar!
    bless $self, $class;
    return $self;
}

sub getData{
    return ${$_[0]};
}

package Crossword::Grid::Guess;
use Carp;
use warnings;
use strict;
use constant GUESS_IDENTIFIER => '#';

sub new{
    my $class = shift;
    my $data  = shift;
    
    Crossword::Toolz::vald_args( $data, [ qw{ arrow wordDescription } ]);
    
    my $self = { cellData => GUESS_IDENTIFIER };

    bless $self, $class;
    $self->append( { arrow => $data->{arrow}, wordDescription => $data->{wordDescription} } );
    return $self;
}

sub append{
    my $self  = shift;
    my $data  = shift;
    
    Crossword::Toolz::vald_args( $data, [ qw{ arrow wordDescription } ]);
    
    my ( $ar, $wd ) = ( $data->{arrow}, $data->{wordDescription} );
    
    confess "ERROR: Re-defining existing Guess->arrows value!" if defined $self->{arrows}->{$ar};
    
    $self->{arrows}->{$ar} = $wd;
}

sub getData{
    return shift->{cellData};
}

package Crossword::Grid::Letter;
# "Crossword::Grid::Letter" will hold 1 letter of a placed word!
use warnings;
use strict;

sub new{
    my $class  = $_[0];
    my $letter = $_[1];
    my $self = \$letter; # ref to scalar!
    bless $self, $class;
    return $self;
}

sub getData{
    return ${$_[0]};
}

package Crossword::DB::Txt;
# NB: NOT Object-Oriented package!
use utf8;
use Carp;
use warnings;
use strict;

use constant WORDS_TXT_DB_FILE        => &Crossword::WORDS_TXT_DB_FILE;
use constant DESCRIPTIONS_TXT_DB_FILE => &Crossword::DESCRIPTIONS_TXT_DB_FILE;

sub queryMaxWordLen{
    open WORD_DATA, '<:utf8', WORDS_TXT_DB_FILE or confess $!;
    $_ = <WORD_DATA>; # Only 1 line is needed, because txt word file is sorted with the longest on top.
    my $len = $1 if (/^\d+#(\d+)#\w+$/);
    close WORD_DATA or confess $!;
    return $len;
}

sub queryWords{
    my $regex = $_[0]->{regex};
    my $len   = $_[0]->{len};
    
    Crossword::logger ( sub{print Crossword::LOG "Crossword::DB::Txt::queryWords(): Tested Regex: [$regex]\n";});

    my $matched_data; # will serve as ref to array of words.
    my $count = 0;

    open WORD_DATA, '<:utf8', WORDS_TXT_DB_FILE or confess $!;
    while (<WORD_DATA>){
        next unless (/^\d+#$len#/);
        if (/^(\d+)#$len#($regex)$/){ # Line format: 17452#7#example
            $matched_data->[$count]->{id}   = $1;
            $matched_data->[$count]->{word} = $2;
            ++$count;
        }
    }
    close WORD_DATA or confess $!;
    return $matched_data;
}

sub queryWordDesc{
    my $word_id = shift;
    
    Crossword::logger ( sub{print Crossword::LOG "Getting desc for word id: [$word_id]...\n";});
    
    my $desc;
    open DESC_DATA, '<:utf8', DESCRIPTIONS_TXT_DB_FILE or confess $!;
    while (<DESC_DATA>){
        next unless (/^$word_id#/);
        if (/^$word_id#(.*)$/){ # Line format: 17452#Word description...
            $desc = $1;
            last;
        }
    }
    close DESC_DATA or confess $!;
    Crossword::logger ( sub{print Crossword::LOG "Returned desc for word id [$word_id]: [$desc]\n";});
    return $desc;
}

package Crossword::DB::Rel;
# NB: NOT Object-Oriented package!
use utf8;
use DBI;
use Carp;
use warnings;
use strict;

sub queryMaxWordLen{
    my $dbh     = shift;
    
    my $ary_ref = $dbh->selectrow_arrayref( 'SELECT max(word_len) FROM words' ) or 
        confess "Couldn't prepare, execute and fetchrow_arrayref for statement: " . $dbh->errstr;
    
    return $ary_ref->[0];
}

sub queryWords{
    my $data = shift;
    my $sth  = shift;
    
    $data->{sth} = $sth;
    Crossword::Toolz::vald_args( $data, [ qw{ regex len sth } ] );
    
    my $regex = $data->{regex};
    my $tbl_ary_ref;
    
    if ( $regex ne '' ){
        Crossword::logger ( sub{print Crossword::LOG
            "Crossword::DB::Rel::queryWords(): Tested Regex: [$regex]\n";});

        $sth->execute( $data->{len}, $regex ) 
            or confess "Couldn't execute statement: "                 . $sth->errstr;
        
        $tbl_ary_ref = $sth->fetchall_arrayref({})
            or confess "Couldn't 'fetchall_arrayref({})' statement: " . $sth->errstr;
    }
    return $tbl_ary_ref;
}

sub queryWordDesc{
    my $id  = shift;
    my $sth = shift;
    
    $sth->execute($id)
        or confess "Couldn't execute statement: "             . $sth->errstr;
    
    my $ary_ref = $sth->fetchrow_arrayref()
        or confess "Couldn't 'fetchrow_arrayref' statement: " . $sth->errstr;
    
    return $ary_ref->[0];
}

package Crossword::Toolz;
# NB: NOT Object-Oriented package!
use Carp;

sub vald_args{
    my $args   = shift;
    my $fields = shift;
    foreach my $field (@$fields){
        confess "ERROR: Calling with missing mandatory argument: <$field>" if not defined $args->{$field};
    }
}

1; # .pm always ends with 'true'!

__END__

=head1 NAME

Crossword - Simple OOP crossword generator with UTF-8 support and
word information loading from text or MySQL database.

=head1 SYNOPSIS

  use Crossword;
  
  my $cw = Crossword->new({ height => 10, width => 12 });
  $cw->fill( { algorithm => 'TraceFull' } );

=head1 DESCRIPTION

Word crossing algorithm is kind of "brute-force search" with
use of regular expressions.
Following crossword generation sub-algorithms are currently
presented:

  - "FishNet" - words are placed like a 'net', loosely crossed.
  
  - "ChuckNorris" - grid is filled as much as possible, but
  there is no intelligence in order to prevent sequences of 
  letters that can never be crossed or form valid words.
  
  - "TraceFull" - grid is filled as much as possible with
  simple intelligence added in order to prevent sequences of
  letters that can never be crossed or form valid words.
  This intelligence is just 'placing letter traces' of all word
  possibilities by axis X, and then try to make crosses by axis Y.

=head1 TO DO

Word placing algorithms must be updated with huge intelligence!

=head1 AUTHOR

Stoyan Tsanev

=head1 COPYRIGHT AND LICENSE

Copyright 2012, Stoyan Tsanev.  All rights reserved.  

This library is free software; you can redistribute it and/or modify it under 
the same terms as Perl itself (L<perlgpl>, L<perlartistic>).

=cut
