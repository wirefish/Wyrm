'use strict';

// This file implements a renderer for a simple markup language used to annotate
// text. It is inspired by markdown, but not meant to be compatible.
//
// Paragraphs are separated by one or more blank lines.
//
// Headings are introduced by one or more hashes.
//
// Horizontal rules are denoted by 3 or more dashes alone on a line.
//
// Unnumbered list items are introduced with a single dash and one or more
// spaces.
//
// Numbered list items are introduced with one or more digits, a dot, and one or
// more spaces.
//
// Paragraphs prefixed with > are block quotes.
//
// Paragraphs prefixed with | are block quotes that preserve line breaks.
//
// **strong** and *emphasis*
//
// Text within backticks creates a link that sends input as if typed by the
// player.

// Given a string that represents a block of text such as a paragraph, returns
// its formatted HTML representation as a new string.
function formatBlock(s) {
    s = s.replace(/\n/g, ' ');
    s = s.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
    s = s.replace(/\*([^\*]+)\*/g, '<em>$1</em>');

    // Convert ellipsis, em- and en-dashes, pipes, and smart quotes.
    s = s.replace(/\.\.\./g, "\u2026")
        .replace(/---/g, "\u2014")
        .replace(/--/g, "\u2013")
        .replace(/\|/g, "\u2223")
        .replace(/'/g, "\u2019")
        .replace(/"([^"]*)"/g, "\u201c$1\u201d");

    // This is a major deviation from the spec: the inline code syntax instead
    // generates links that send input to the server, as if it had been typed by
    // the player.
    //
    // If the value begins with an article, that article is removed from the
    // resulting input.
    //
    // If there is a prefix ending with a colon, it must consist of a
    // comma-separated series of tokens. These tokens control the link style
    // and/or the input sent when the link is followed.
    //
    // The final token in the list is prepended to the input.
    //
    // All tokens in the list are additionally used as styles for the link. The
    // exception is that, if a token is empty, no subsequent tokens are applied
    // as styles.
    s = s.replace(/`(?:([a-z ,]+):)?((?:A|a|An|an|The|the) +)?([^`]*)`/g,
                  function(full, prefix, article, value) {
                      var action;
                      prefix = prefix ? prefix.split(',') : [];
                      if (prefix.length && prefix[prefix.length - 1])
                          action = 'sendInput(\'' + prefix[prefix.length - 1] + ' ' + value + '\')';
                      else
                          action = 'sendInput(\'' + value + '\')';
                      var num_styles = prefix.concat(['']).indexOf('');
                      return '<span class="link ' + prefix.slice(0, num_styles).join(' ') +
                          '" onclick="' + action + '">' + (article || '') + value + '</span>';
                  });

    // Another deviation: only inline links are used, and the title attribute isn't supported.
    s = s.replace(/\[([^\]]+)\]\(([^)]+)\)/, '<a href="$2">$1</a>');

    return s;
}

// Returns an element with the specified tag and (optional) className,
// containing the innerHTML that results from formatting the given content.
function makeTextElement(tag, content, className) {
    var element = document.createElement(tag);
    if (className)
        element.className = className;
    element.innerHTML = formatBlock(content);
    return element;
}

// Given a list of items which may be strings or elements, returns a new list
// that replaces the strings with elements created by calling makeTextElement().
function formatStrings(tag, items, className) {
    return items.map(function(item) {
        if (typeof item === 'string')
            return makeTextElement(tag, item, className);
        else
            return item;
    });
}

function wrapElements(tag, children, className) {
    var element = document.createElement(tag);
    if (className != undefined)
        element.className = className;
    for (var i = 0; i < children.length; ++i)
        element.appendChild(children[i]);
    return element;
}

function makeList(items) {
    return wrapElements('ul', items.map(function (s) {return makeTextElement('li', s); }));
}

// Returns an array of elements that represent the formatted version of the
// given text.
function formatText(s, default_paragraph_tag = 'p') {
    var output = [];
    var list = null;

    // Remove all whitespace at the ends of lines and convert tabs to spaces.
    s = s.replace(/[ \t]*\r?\n/g, '\n').replace(/\t/g, '    ');

    var blocks = s.split(/\n{2,}/);
    for (var i = 0; i < blocks.length; ++i) {
        var b = blocks[i].trim();
        var m;
        if (m = /^ *(#{1,6}) *([^\n]+?) *#*$/.exec(b)) {
            list = null;
            output.push(makeTextElement('h' + m[1].length, m[2]));
        } else if (m = /^\-{3,} *$/.exec(b)) {
            list = null;
            output.push(document.createElement('hr'));
        } else if (m = /^> ?/.exec(b)) {
            list = null;
            output.push(makeTextElement('blockquote', b.replace(/^ *>/gm, '')));
        } else if (m = /^\| ?/.exec(b)) {
            list = null;
            output.push(makeTextElement('blockquote',
                                        b.replace(/^ *\|/gm, '').replace(/\n/g, '<br>')));
        } else if (m = /^\- +/.exec(b)) {
            if (list == null || list.tagName != 'UL') {
                list = document.createElement('ul');
                output.push(list);
            }
            list.appendChild(makeTextElement('li', b.substr(m[0].length)));
        } else if (m = /^\d+\. +/.exec(b)) {
            if (list == null || list.tagName != 'OL') {
                list = document.createElement('ol');
                output.push(list);
            }
            list.appendChild(makeTextElement('li', b.substr(m[0].length)));
        } else {
            list = null;
            output.push(makeTextElement(default_paragraph_tag, b));
        }
    }

    return output;
}

// Returns a new string constructed by removing the leading definite or
// indefinite article from the given string.
function removeArticle(s)
{
    return s.replace(/^(a |an |the )/, '');
}

// Returns a new string constructed by replacing the leading indefinite article,
// if any, with a definite article.
function makeDefinite(s)
{
    return this.replace(/^(a |an )/, 'the ');
}

// Applies a heuristic to return the plural form of the given word.
function pluralizeWord(word)
{
    if (['s', 'x', 'z', 'o', 'ch', 'sh'].some(function(s) { return word.endsWith(s); }))
        return word + 'es';
    else
        return word + 's';
}

// The inverse of pluralizeWord().
function singularizeWord(word)
{
    if (word.endsWith('es')) {
        var prefix = word.substr(0, word.length - 2);
        if (['s', 'x', 'z', 'o', 'ch', 'sh'].some(function(s) { return prefix.endsWith(s); }))
            return prefix;
    }
    if (word.endsWith('s'))
        return word.substr(0, word.length - 1);
    return word;
}

var IRREGULAR_VERBS = {'is': 'are'};

// Given a verb phrase where the verb is in third person singular form, e.g.
// 'is', 'stabs', or 'watches the clock', returns a phrase where the verb is
// transformed into third person plural form, e.g. 'are', 'stab', or 'watch the
// clock'.
function makeVerbPlural(s)
{
    var words = s.split(' ');
    if (words[0] in IRREGULAR_VERBS)
        words[0] = IRREGULAR_VERBS[words[0]];
    else
        words[0] = singularizeWord(words[0]);
    return words.join(' ');
}

var PREPOSITIONS = new Set([
    'about', 'above', 'after', 'against', 'below', 'by', 'for', 'from', 'in',
    'inside', 'like', 'near', 'of', 'on', 'outside', 'over', 'to', 'under',
    'upon', 'with'
]);

// Given a noun phrase like 'a pot of ink', returns the plural form of the
// phrase, e.g. 'pots of ink'. If the input contains an explicit pattern of the
// form (y) or (x|y), the plural is formed by removing the article and replacing
// the pattern with y. Otherwise, a heuristic is used.
function makePlural(s, count)
{
    s = removeArticle(s);

    // Look for an explicit rule.
    var plural = s.replace(/\((?:\w*\|)?(\w+)\)/, '$1');
    if (plural != s)
        return plural;

    // Find the noun to modify. It is either the last word before the first
    // preposition, or the last word in the phrase if there is no preposition.
    var words = s.split();
    var prep_index = words.findIndex(function (x) { return PREPOSITIONS.has(x); });
    var noun_index = (prep_index <= 0) ? words.length - 1 : prep_index - 1;
    words[noun_index] = pluralizeWord(words[noun_index]);
    var result = words.join(' ');

    if (count != undefined)
        result = count + ' ' + result;

    return result;
}

// Given a noun phrase that may include an explicit pluralization rule, applies
// the rule to return the singular form. If there is no rule, returns the
// original string.
function makeSingular(s)
{
    return s.replace(/\(\w+\)/, '').replace(/\((\w+)\|\w+\)/, '$1');
}
