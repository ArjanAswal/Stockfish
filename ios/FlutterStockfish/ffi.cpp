#include "../Stockfish/src/bitboard.h"
#include "../Stockfish/src/endgame.h"
#include "../Stockfish/src/position.h"
#include "../Stockfish/src/search.h"
#include "../Stockfish/src/thread.h"
#include "../Stockfish/src/tt.h"
#include "../Stockfish/src/uci.h"
#include "../Stockfish/src/syzygy/tbprobe.h"

#include "ffi.h"

namespace PSQT {
  void init();
}

void stockfish_init(void) {
	UCI::init(Options);
	Tune::init();
	PSQT::init();
	Bitboards::init();
	Position::init();
	Bitbases::init();
	Endgames::init();
    Threads.set(size_t(Options["Threads"]));
    Search::clear();
    Eval::init_NNUE();
}
