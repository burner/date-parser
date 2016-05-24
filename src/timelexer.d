/**
 * Boost Software License - Version 1.0 - August 17th, 2003
 *
 * Permission is hereby granted, free of charge, to any person or organization
 * obtaining a copy of the software and accompanying documentation covered by
 * this license (the "Software") to use, reproduce, display, distribute,
 * execute, and transmit the Software, and to prepare derivative works of the
 * Software, and to permit third-parties to whom the Software is furnished to
 * do so, all subject to the following:
 *
 * The copyright notices in the Software and this entire statement, including
 * the above license grant, this restriction and the following disclaimer,
 * must be included in all copies of the Software, in whole or in part, and
 * all derivative works of the Software, unless such copies or derivative
 * works are solely in the form of machine-executable object code generated by
 * a source language processor.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT. IN NO EVENT
 * SHALL THE COPYRIGHT HOLDERS OR ANYONE DISTRIBUTING THE SOFTWARE BE LIABLE
 * FOR ANY DAMAGES OR OTHER LIABILITY, WHETHER IN CONTRACT, TORT OR OTHERWISE,
 * ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

module dateparser.timelexer;

debug(dateparser) import std.stdio;
import std.range;
import std.traits;
import std.regex;
import dateparser.splitter;

package:

// Needs to be explicitly flagged global for the backwards compatible
// version of splitterWithMatches
enum split_decimal = ctRegex!(`([\.,])`, "g");

/**
* This function breaks the time string into lexical units (tokens), which
* can be parsed by the parser. Lexical units are demarcated by changes in
* the character set, so any continuous string of letters is considered
* one unit, any continuous string of numbers is considered one unit.
*
* The main complication arises from the fact that dots ('.') can be used
* both as separators (e.g. "Sep.20.2009") or decimal points (e.g.
* "4:30:21.447"). As such, it is necessary to read the full context of
* any dot-separated strings before breaking it into tokens; as such, this
* function maintains a "token stack", for when the ambiguous context
* demands that multiple tokens be parsed at once.
*
* Params:
*     r = the range to parse
* Returns:
*     a input range of strings
*/
auto timeLexer(Range)(Range r) if (isInputRange!Range && isSomeChar!(ElementEncodingType!Range))
{
    return TimeLexerResult!Range(r);
}

// Issue 15831: This should be a Voldemort type, but due to linker slowdown
// it's a good idea to put this outside so we don't slowdown people's build
// times
struct TimeLexerResult(Range)
{
private:
    Range source;
    string charStack;
    string[] tokenStack;
    string token;
    enum State
    {
        EMPTY,
        ALPHA,
        NUMERIC,
        ALPHA_PERIOD,
        PERIOD,
        NUMERIC_PERIOD
    }

public:
    this(Range r)
    {
        source = r;
        popFront();
    }

    auto front() @property
    {
        return token;
    }

    void popFront()
    {
        import std.algorithm.searching : canFind, count;
        import std.uni : isNumber, isSpace, isAlpha;

        if (tokenStack.length > 0)
        {
            immutable f = tokenStack.front;
            tokenStack.popFront;
            token = f;
            return;
        }

        bool seenLetters = false;
        State state = State.EMPTY;
        token = string.init;

        while (!source.empty || !charStack.empty)
        {
            // We only realize that we've reached the end of a token when we
            // find a character that's not part of the current token - since
            // that character may be part of the next token, it's stored in the
            // charStack.
            dchar nextChar;

            if (!charStack.empty)
            {
                nextChar = charStack.front;
                charStack.popFront;
            }
            else
            {
                nextChar = source.front;
                source.popFront;
            }

            if (state == State.EMPTY)
            {
                debug(dateparser) writeln("EMPTY");
                // First character of the token - determines if we're starting
                // to parse a word, a number or something else.
                token ~= nextChar;

                if (nextChar.isAlpha)
                    state = State.ALPHA;
                else if (nextChar.isNumber)
                    state = State.NUMERIC;
                else if (nextChar.isSpace)
                {
                    token = " ";
                    break; //emit token
                }
                else
                    break; //emit token
                debug(dateparser) writeln("TOKEN ", token, " STATE ", state);
            }
            else if (state == State.ALPHA)
            {
                debug(dateparser) writeln("STATE ", state, " nextChar: ", nextChar);
                // If we've already started reading a word, we keep reading
                // letters until we find something that's not part of a word.
                seenLetters = true;

                if (nextChar.isAlpha)
                    token ~= nextChar;
                else if (nextChar == '.')
                {
                    token ~= nextChar;
                    state = State.ALPHA_PERIOD;
                }
                else
                {
                    charStack ~= nextChar;
                    break; //emit token
                }
            }
            else if (state == State.NUMERIC)
            {
                // If we've already started reading a number, we keep reading
                // numbers until we find something that doesn't fit.
                debug(dateparser) writeln("STATE ", state, " nextChar: ", nextChar);
                if (nextChar.isNumber)
                    token ~= nextChar;
                else if (nextChar == '.' || (nextChar == ',' && token.length >= 2))
                {
                    token ~= nextChar;
                    state = State.NUMERIC_PERIOD;
                }
                else
                {
                    charStack ~= nextChar;
                    debug(dateparser) writeln("charStack add: ", charStack);
                    break; //emit token
                }
            }
            else if (state == State.ALPHA_PERIOD)
            {
                debug(dateparser) writeln("STATE ", state, " nextChar: ", nextChar);
                // If we've seen some letters and a dot separator, continue
                // parsing, and the tokens will be broken up later.
                seenLetters = true;
                if (nextChar == '.' || nextChar.isAlpha)
                    token ~= nextChar;
                else if (nextChar.isNumber && token[$ - 1] == '.')
                {
                    token ~= nextChar;
                    state = State.NUMERIC_PERIOD;
                }
                else
                {
                    charStack ~= nextChar;
                    break; //emit token
                }
            }
            else if (state == State.NUMERIC_PERIOD)
            {
                debug(dateparser) writeln("STATE ", state, " nextChar: ", nextChar);
                // If we've seen at least one dot separator, keep going, we'll
                // break up the tokens later.
                if (nextChar == '.' || nextChar.isNumber)
                    token ~= nextChar;
                else if (nextChar.isAlpha && token[$ - 1] == '.')
                {
                    token ~= nextChar;
                    state = State.ALPHA_PERIOD;
                }
                else
                {
                    charStack ~= nextChar;
                    break; //emit token
                }
            }
        }

        debug(dateparser) writeln("STATE ", state, " seenLetters: ", seenLetters);
        if ((state == State.ALPHA_PERIOD || state == State.NUMERIC_PERIOD)
                && (seenLetters || token.count('.') > 1
                || (token[$ - 1] == '.' || token[$ - 1] == ',')))
            if ((state == State.ALPHA_PERIOD
                    || state == State.NUMERIC_PERIOD) && (seenLetters
                    || token.count('.') > 1 || (token[$ - 1] == '.' || token[$ - 1] == ',')))
            {
                auto l = splitterWithMatches(token[], split_decimal);
                token = l.front;
                l.popFront;

                foreach (tok; l)
                    if (tok.length > 0)
                        tokenStack ~= tok;
            }

        if (state == State.NUMERIC_PERIOD && !token.canFind('.'))
            token = token.replace(",", ".");
    }

    bool empty()() @property
    {
        return token.empty && source.empty && charStack.empty && tokenStack.empty;
    }
}

unittest
{
    import std.algorithm.comparison : equal;

    assert("Thu Sep 25 10:36:28 BRST 2003".timeLexer.equal(
        ["Thu", " ", "Sep", " ", "25", " ",
         "10", ":", "36", ":", "28", " ",
         "BRST", " ", "2003"]
    ));

    assert("2003-09-25T10:49:41.5-03:00".timeLexer.equal(
        ["2003", "-", "09", "-", "25", "T",
         "10", ":", "49", ":", "41.5", "-",
         "03", ":", "00"]
    ));
}

unittest
{
    import std.internal.test.dummyrange : ReferenceInputRange;
    import std.algorithm.comparison : equal;

    auto a = new ReferenceInputRange!dchar("10:10");
    assert(a.timeLexer.equal(["10", ":", "10"]));

    auto b = new ReferenceInputRange!dchar("Thu Sep 10:36:28");
    assert(b.timeLexer.equal(["Thu", " ", "Sep", " ", "10", ":", "36", ":", "28"]));
}