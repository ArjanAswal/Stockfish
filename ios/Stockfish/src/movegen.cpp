/*
  Stockfish, a UCI chess playing engine derived from Glaurung 2.1
  Copyright (C) 2004-2020 The Stockfish developers (see AUTHORS file)

  Stockfish is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Stockfish is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#include <cassert>

#include "movegen.h"
#include "position.h"

namespace {

  template<GenType Type, Direction D>
  ExtMove* make_promotions(ExtMove* moveList, Square to, Square ksq) {

    if (Type == CAPTURES || Type == EVASIONS || Type == NON_EVASIONS)
    {
        *moveList++ = make<PROMOTION>(to - D, to, QUEEN);
        if (attacks_bb<KNIGHT>(to) & ksq)
            *moveList++ = make<PROMOTION>(to - D, to, KNIGHT);
    }

    if (Type == QUIETS || Type == EVASIONS || Type == NON_EVASIONS)
    {
        *moveList++ = make<PROMOTION>(to - D, to, ROOK);
        *moveList++ = make<PROMOTION>(to - D, to, BISHOP);
        if (!(attacks_bb<KNIGHT>(to) & ksq))
            *moveList++ = make<PROMOTION>(to - D, to, KNIGHT);
    }

    return moveList;
  }


  template<Color Us, GenType Type>
  ExtMove* generate_pawn_moves(const Position& pos, ExtMove* moveList, Bitboard target) {

    constexpr Color     Them     = ~Us;
    constexpr Bitboard  TRank7BB = (Us == WHITE ? Rank7BB    : Rank2BB);
    constexpr Bitboard  TRank3BB = (Us == WHITE ? Rank3BB    : Rank6BB);
    constexpr Direction Up       = pawn_push(Us);
    constexpr Direction UpRight  = (Us == WHITE ? NORTH_EAST : SOUTH_WEST);
    constexpr Direction UpLeft   = (Us == WHITE ? NORTH_WEST : SOUTH_EAST);

    const Square ksq = pos.square<KING>(Them);
    Bitboard emptySquares;

    Bitboard pawnsOn7    = pos.pieces(Us, PAWN) &  TRank7BB;
    Bitboard pawnsNotOn7 = pos.pieces(Us, PAWN) & ~TRank7BB;

    Bitboard enemies = (Type == EVASIONS ? pos.pieces(Them) & target:
                        Type == CAPTURES ? target : pos.pieces(Them));

    // Single and double pawn pushes, no promotions
    if (Type != CAPTURES)
    {
        emptySquares = (Type == QUIETS || Type == QUIET_CHECKS ? target : ~pos.pieces());

        Bitboard b1 = shift<Up>(pawnsNotOn7)   & emptySquares;
        Bitboard b2 = shift<Up>(b1 & TRank3BB) & emptySquares;

        if (Type == EVASIONS) // Consider only blocking squares
        {
            b1 &= target;
            b2 &= target;
        }

        if (Type == QUIET_CHECKS)
        {
            b1 &= pawn_attacks_bb(Them, ksq);
            b2 &= pawn_attacks_bb(Them, ksq);

            // Add pawn pushes which give discovered check. This is possible only
            // if the pawn is not on the same file as the enemy king, because we
            // don't generate captures. Note that a possible discovery check
            // promotion has been already generated amongst the captures.
            Bitboard dcCandidateQuiets = pos.blockers_for_king(Them) & pawnsNotOn7;
            if (dcCandidateQuiets)
            {
                Bitboard dc1 = shift<Up>(dcCandidateQuiets) & emptySquares & ~file_bb(ksq);
                Bitboard dc2 = shift<Up>(dc1 & TRank3BB) & emptySquares;

                b1 |= dc1;
                b2 |= dc2;
            }
        }

        while (b1)
        {
            Square to = pop_lsb(&b1);
            *moveList++ = make_move(to - Up, to);
        }

        while (b2)
        {
            Square to = pop_lsb(&b2);
            *moveList++ = make_move(to - Up - Up, to);
        }
    }

    // Promotions and underpromotions
    if (pawnsOn7)
    {
        if (Type == CAPTURES)
            emptySquares = ~pos.pieces();

        if (Type == EVASIONS)
            emptySquares &= target;

        Bitboard b1 = shift<UpRight>(pawnsOn7) & enemies;
        Bitboard b2 = shift<UpLeft >(pawnsOn7) & enemies;
        Bitboard b3 = shift<Up     >(pawnsOn7) & emptySquares;

        while (b1)
            moveList = make_promotions<Type, UpRight>(moveList, pop_lsb(&b1), ksq);

        while (b2)
            moveList = make_promotions<Type, UpLeft >(moveList, pop_lsb(&b2), ksq);

        while (b3)
            moveList = make_promotions<Type, Up     >(moveList, pop_lsb(&b3), ksq);
    }

    // Standard and en-passant captures
    if (Type == CAPTURES || Type == EVASIONS || Type == NON_EVASIONS)
    {
        Bitboard b1 = shift<UpRight>(pawnsNotOn7) & enemies;
        Bitboard b2 = shift<UpLeft >(pawnsNotOn7) & enemies;

        while (b1)
        {
            Square to = pop_lsb(&b1);
            *moveList++ = make_move(to - UpRight, to);
        }

        while (b2)
        {
            Square to = pop_lsb(&b2);
            *moveList++ = make_move(to - UpLeft, to);
        }

        if (pos.ep_square() != SQ_NONE)
        {
            assert(rank_of(pos.ep_square()) == relative_rank(Us, RANK_6));

            // An en passant capture can be an evasion only if the checking piece
            // is the double pushed pawn and so is in the target. Otherwise this
            // is a discovery check and we are forced to do otherwise.
            if (Type == EVASIONS && !(target & (pos.ep_square() - Up)))
                return moveList;

            b1 = pawnsNotOn7 & pawn_attacks_bb(Them, pos.ep_square());

            assert(b1);

            while (b1)
                *moveList++ = make<ENPASSANT>(pop_lsb(&b1), pos.ep_square());
        }
    }

    return moveList;
  }


  template<Color Us, PieceType Pt, bool Checks>
  ExtMove* generate_moves(const Position& pos, ExtMove* moveList, Bitboard target) {

    static_assert(Pt != KING && Pt != PAWN, "Unsupported piece type in generate_moves()");

    const Square* pl = pos.squares<Pt>(Us);

    for (Square from = *pl; from != SQ_NONE; from = *++pl)
    {
        if (Checks)
        {
            if (    (Pt == BISHOP || Pt == ROOK || Pt == QUEEN)
                && !(attacks_bb<Pt>(from) & target & pos.check_squares(Pt)))
                continue;

            if (pos.blockers_for_king(~Us) & from)
                continue;
        }

        Bitboard b = attacks_bb<Pt>(from, pos.pieces()) & target;

        if (Checks)
            b &= pos.check_squares(Pt);

        while (b)
            *moveList++ = make_move(from, pop_lsb(&b));
    }

    return moveList;
  }


  template<Color Us, GenType Type>
  ExtMove* generate_all(const Position& pos, ExtMove* moveList) {
    constexpr bool Checks = Type == QUIET_CHECKS; // Reduce template instantations
    Bitboard target;

    switch (Type)
    {
        case CAPTURES:
            target =  pos.pieces(~Us);
            break;
        case QUIETS:
        case QUIET_CHECKS:
            target = ~pos.pieces();
            break;
        case EVASIONS:
        {
            Square checksq = lsb(pos.checkers());
            target = between_bb(pos.square<KING>(Us), checksq) | checksq;
            break;
        }
        case NON_EVASIONS:
            target = ~pos.pieces(Us);
            break;
        default:
            static_assert(true, "Unsupported type in generate_all()");
    }

    moveList = generate_pawn_moves<Us, Type>(pos, moveList, target);
    moveList = generate_moves<Us, KNIGHT, Checks>(pos, moveList, target);
    moveList = generate_moves<Us, BISHOP, Checks>(pos, moveList, target);
    moveList = generate_moves<Us,   ROOK, Checks>(pos, moveList, target);
    moveList = generate_moves<Us,  QUEEN, Checks>(pos, moveList, target);

    if (Type != QUIET_CHECKS && Type != EVASIONS)
    {
        Square ksq = pos.square<KING>(Us);
        Bitboard b = attacks_bb<KING>(ksq) & target;
        while (b)
            *moveList++ = make_move(ksq, pop_lsb(&b));

        if ((Type != CAPTURES) && pos.can_castle(Us & ANY_CASTLING))
            for (CastlingRights cr : { Us & KING_SIDE, Us & QUEEN_SIDE } )
                if (!pos.castling_impeded(cr) && pos.can_castle(cr))
                    *moveList++ = make<CASTLING>(ksq, pos.castling_rook_square(cr));
    }

    return moveList;
  }

} // namespace


/// <CAPTURES>     Generates all pseudo-legal captures plus queen and checking knight promotions
/// <QUIETS>       Generates all pseudo-legal non-captures and underpromotions(except checking knight)
/// <NON_EVASIONS> Generates all pseudo-legal captures and non-captures
///
/// Returns a pointer to the end of the move list.

template<GenType Type>
ExtMove* generate(const Position& pos, ExtMove* moveList) {

  static_assert(Type == CAPTURES || Type == QUIETS || Type == NON_EVASIONS, "Unsupported type in generate()");
  assert(!pos.checkers());

  Color us = pos.side_to_move();

  return us == WHITE ? generate_all<WHITE, Type>(pos, moveList)
                     : generate_all<BLACK, Type>(pos, moveList);
}

// Explicit template instantiations
template ExtMove* generate<CAPTURES>(const Position&, ExtMove*);
template ExtMove* generate<QUIETS>(const Position&, ExtMove*);
template ExtMove* generate<NON_EVASIONS>(const Position&, ExtMove*);


/// generate<QUIET_CHECKS> generates all pseudo-legal non-captures.
/// Returns a pointer to the end of the move list.
template<>
ExtMove* generate<QUIET_CHECKS>(const Position& pos, ExtMove* moveList) {

  assert(!pos.checkers());

  Color us = pos.side_to_move();
  Bitboard dc = pos.blockers_for_king(~us) & pos.pieces(us) & ~pos.pieces(PAWN);

  while (dc)
  {
     Square from = pop_lsb(&dc);
     PieceType pt = type_of(pos.piece_on(from));

     Bitboard b = attacks_bb(pt, from, pos.pieces()) & ~pos.pieces();

     if (pt == KING)
         b &= ~attacks_bb<QUEEN>(pos.square<KING>(~us));

     while (b)
         *moveList++ = make_move(from, pop_lsb(&b));
  }

  return us == WHITE ? generate_all<WHITE, QUIET_CHECKS>(pos, moveList)
                     : generate_all<BLACK, QUIET_CHECKS>(pos, moveList);
}


/// generate<EVASIONS> generates all pseudo-legal check evasions when the side
/// to move is in check. Returns a pointer to the end of the move list.
template<>
ExtMove* generate<EVASIONS>(const Position& pos, ExtMove* moveList) {

  assert(pos.checkers());

  Color us = pos.side_to_move();
  Square ksq = pos.square<KING>(us);
  Bitboard sliderAttacks = 0;
  Bitboard sliders = pos.checkers() & ~pos.pieces(KNIGHT, PAWN);

  // Find all the squares attacked by slider checkers. We will remove them from
  // the king evasions in order to skip known illegal moves, which avoids any
  // useless legality checks later on.
  while (sliders)
      sliderAttacks |= line_bb(ksq, pop_lsb(&sliders)) & ~pos.checkers();

  // Generate evasions for king, capture and non capture moves
  Bitboard b = attacks_bb<KING>(ksq) & ~pos.pieces(us) & ~sliderAttacks;
  while (b)
      *moveList++ = make_move(ksq, pop_lsb(&b));

  if (more_than_one(pos.checkers()))
      return moveList; // Double check, only a king move can save the day

  // Generate blocking evasions or captures of the checking piece
  return us == WHITE ? generate_all<WHITE, EVASIONS>(pos, moveList)
                     : generate_all<BLACK, EVASIONS>(pos, moveList);
}


/// generate<LEGAL> generates all the legal moves in the given position

template<>
ExtMove* generate<LEGAL>(const Position& pos, ExtMove* moveList) {

  Color us = pos.side_to_move();
  Bitboard pinned = pos.blockers_for_king(us) & pos.pieces(us);
  Square ksq = pos.square<KING>(us);
  ExtMove* cur = moveList;

  moveList = pos.checkers() ? generate<EVASIONS    >(pos, moveList)
                            : generate<NON_EVASIONS>(pos, moveList);
  while (cur != moveList)
      if (   (pinned || from_sq(*cur) == ksq || type_of(*cur) == ENPASSANT)
          && !pos.legal(*cur))
          *cur = (--moveList)->move;
      else
          ++cur;

  return moveList;
}
