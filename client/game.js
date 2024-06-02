'use strict';

var max_blocks = 500;

var command_history = new Array(100);
var command_pos = 0;

var ws = null;
var map = null;
var handler = null;

function resize() {
    map.resize();
}
window.onresize = resize;

function link(text, type, command) {
    return '`{0}:{1}:{2}`'.format(
        type ? type : "",
        text,
        command ? command : "");
}

function look(s) {
    return link(s, 'look', 'look at $');
}

function setIcon(element, type, icon) {
    if (icon)
        element.className = '{0}_icons {0}_{1}'.format(type, icon);
}

//
// Updates a stat bar to reflect a current and maximum value.
//
function updateBar(id, current, max) {
    var p = max ? Math.min(100, 100.0 * current / max) : 0;
    var bar = document.getElementById(id);
    bar.children[0].style.width = p + "%";
    bar.children[1].innerHTML = current + " / " + max;
}

function updatePlayerBio(name, icon, level, race) {
    var summary = name ?
        '{0}, level {1} {2}'.format(name, level, race) :
        'level {0} {1}'.format(level, race);
    document.getElementById("player_name").innerHTML = summary;
    setIcon(document.getElementById("player_icon"), "avatar", icon);
}

// Appends a block element to a scrollable text pane, removing the oldest block
// first if the maximum number of blocks would be exceeded.
function appendBlock(block, containerId = 'main_text') {
    var container = document.getElementById(containerId);
    if (container.childNodes.length >= max_blocks)
        container.removeChild(container.firstChild);
    container.appendChild(block);
    container.scrollTop = container.scrollHeight;
}

// Panes in left-to-right order.
var panes = ["inventory", "equipment", "combat", "skills", "quests", "chat"];

// An object that encapsulates functions callable based on messages from the
// server.
function MessageHandler() {
    // The cached properties for the player's avatar.
    this.avatar = {};

    // The cached properties of neighbors.
    this.neighbors = {};

    // Enemies that are currently in combat with the player.
    this.enemies = new Set();

    // The enemy that is targeted by player attacks.
    this.enemy_target = undefined;

    // True to show paths, etc. for debugging.
    this.debug = true;

    // Select the inventory pane by default.
    this.currentPane = 'inventory';
}

MessageHandler.prototype.showPane = function(button_id) {
    document.getElementById(this.currentPane).className = 'button toggle_off';
    document.getElementById(this.currentPane + '_pane').style.display = 'none';

    this.currentPane = button_id;

    document.getElementById(this.currentPane).className = 'button toggle_on';
    document.getElementById(this.currentPane + '_pane').style.display = 'block';
}

MessageHandler.prototype.cyclePane = function(dir) {
    var curr = this.currentPane;
    var i = panes.findIndex((x) => (x == curr));
    if (dir == 1)
        i = (i + 1) % panes.length;
    else
        i = (i + panes.length - 1) % panes.length;
    this.showPane(panes[i]);
}

MessageHandler.prototype.showRaw = function(text) {
    var element = document.createElement("pre");
    element.innerHTML = text;
    appendBlock(element);
}

// Display game text in the style defined by the given class.
MessageHandler.prototype.showText = function(text, className) {
    appendBlock(wrapElements('div', formatText(text), className));
}

MessageHandler.prototype.showNotice = function(text) {
    this.showText(text, 'notice');
}

MessageHandler.prototype.showTutorial = function(text) {
    this.showText(text, 'tutorial');
}

MessageHandler.prototype.showError = function(text) {
    this.showText(text, 'error');
}

MessageHandler.prototype.showHelp = function(text) {
    // TODO: look for links to "see also" topics and format them appropriately.
    this.showText(text, 'help');
}

MessageHandler.prototype.showMap = function(location_name, region, subregion, radius, ...rooms) {
    var sep = "\u2002\u00b7\u2002";

    document.getElementById("location_name").innerHTML = location_name;
    if (subregion)
        document.getElementById("zone_name").innerHTML = region + sep + subregion;
    else
        document.getElementById("zone_name").innerHTML = region;
    map.update(radius, rooms);
    map.render();
}

MessageHandler.prototype.updateAvatar = function(properties) {
    // Update the cached properties.
    this.avatar = Object.assign({}, this.avatar, properties);

    // Update UI elements that have changed.
    if (properties.name || properties.icon || properties.level || properties.race)
        updatePlayerBio(this.avatar.name, this.avatar.icon,
                        this.avatar.level, this.avatar.race);
    if (properties.health || properties.max_health)
        updateBar('player_health', this.avatar.health, this.avatar.max_health);
    if (properties.energy || properties.max_energy)
        updateBar('player_energy', this.avatar.energy, this.avatar.max_energy);
    if (properties.xp || properties.max_xp)
        updateBar('player_xp', this.avatar.xp, this.avatar.max_xp);
}

MessageHandler.prototype.showAura = function(key, icon) {
    var id = 'aura_' + key;
    var item = document.getElementById(id);
    if (!item) {
        item = document.createElement('div');
        item.id = id;
        item.className = 'show_aura';
        setIcon(item, icon);
        document.getElementById('player_auras').insertBefore(item, null);
    }
}

MessageHandler.prototype.hideAura = function(key) {
    var item = document.getElementById('aura_' + key);
    if (item) {
        item.addEventListener('animationend', function (event) {
            this.parentNode.removeChild(this);
        });
        item.className = 'hide_aura';
    }
}

function findInventoryDivAfter(sort_key, item_divs) {
    for (const div of item_divs) {
        if (Number(div.getAttribute("jade_sort_key")) > sort_key)
            return div;
    }
    return null;
}

MessageHandler.prototype.updateInventory = function(items) {
    var contents_div = document.getElementById('inventory_contents');

    for (const id in items) {
        var div = document.getElementById('inv_' + id);
        const item = items[id];
        if (item == null) {
            // Remove item.
            if (div)
                div.parentNode.removeChild(div);
        } else {
            // Add or update item.
            const [icon, brief, sort_key] = item;
            if (div) {
                div.children[1].innerHTML = brief;
            } else {
                div = document.createElement('div');
                div.id = 'inv_' + id;
                div.setAttribute("jade_sort_key", sort_key);

                var icon_div = document.createElement('div');
                div.appendChild(icon_div);
                setIcon(icon_div, "inventory", icon);

                var brief_div = document.createElement('div');
                div.appendChild(brief_div);
                brief_div.innerHTML = brief;

                contents_div.insertBefore(
                    div,
                    findInventoryDivAfter(sort_key, contents_div.children));
            }
        }
    }
}

MessageHandler.prototype.updateEquipment = function(equipment) {
    for (const slot in equipment) {
        var div = document.getElementById('equip_' + slot);
        if (equipment[slot]) {
            const [icon, brief] = equipment[slot];

            var icon_div = document.createElement('div');
            div.appendChild(icon_div);
            setIcon(icon_div, "inventory", icon);

            var brief_div = document.createElement('div');
            div.appendChild(brief_div);
            brief_div.innerHTML = brief;
        } else {
            div.innerHTML = null;
        }
    }
}

function createDiv(id, num_children) {
    var div = document.createElement('div');
    div.id = id;
    for (var i = 0; i < num_children; ++i) {
        var child = document.createElement('div');
        div.appendChild(child);
    }
    return div;
}

MessageHandler.prototype.updateCombat = function(attack, defense, speed, damage,
                                                 traits, damage_types) {
    document.getElementById('attack').innerHTML = `Attack<br/>${attack}`;
    document.getElementById('defense').innerHTML = `Defense<br/>${defense}`;
    document.getElementById('speed').innerHTML = `Speed<br/>${speed}`;
    document.getElementById('damage').innerHTML = `Damage<br/>${damage}`;

    if (traits) {
        var parent = document.getElementById('combat_traits');
        for (const [name, value] of traits) {
            const div_id = 'trait_' + name;
            var div = document.getElementById(div_id);
            if (div) {
                div.children[1].innerHTML = value;
            } else {
                div = createDiv(div_id, 2);
                div.children[0].innerHTML = name.capitalize();
                div.children[1].innerHTML = value;
                parent.appendChild(div);
            }
        }
    }

    if (damage_types) {
        for (const [key, name, affinity, resistance] of damage_types) {
        }
    }
}

MessageHandler.prototype.updateSkills = function(karma, ...skills) {
    document.getElementById('unspent_karma').innerHTML = `Unspent karma: ${karma}`;

    if (!skills)
        return;

    var skills_pane = document.getElementById('skills_pane');
    for (const [key, name, rank, max_rank] of skills) {
        var div_id = 'skill_' + key;
        var div = document.getElementById(div_id);

        if (name === undefined) {
            // Remove the entry.
            if (div)
                div.parentNode.removeChild(div);
        } else if (div) {
            // Update an existing entry.
            if (max_rank > 0)
                div.children[1].innerHTML = `${rank} / ${max_rank}`;
        } else {
            // Find the existing skill entry before which to insert the new one,
            // based on ordering by skill name. Ignore the first child, which is
            // the unspent karma and not a skill.
            var next_div = null;
            for (var j = 1; j < skills_pane.children.length; ++j) {
                var child = skills_pane.children[j];
                if (name < child.children[0].innerHTML) {
                    next_div = child;
                    break;
                }
            }

            // Create a new entry.
            div = createDiv(div_id, 3);
            div.children[0].innerHTML = name;
            div.children[0].onclick = function () { sendInput(`skill ${name}`); };
            if (max_rank > 0)
                div.children[1].innerHTML = `${rank} / ${max_rank}`;

            document.getElementById('skills_pane').insertBefore(div, next_div);
        }
    }
}

MessageHandler.prototype.updateQuests = function(...quests) {
    if (!quests)
        return;

    var quests_pane = document.getElementById('quests_pane');
    for (const [key, name, level, summary] of quests) {
        const div_id = 'quest_' + key;
        var div = document.getElementById(div_id);

        if (name === undefined) {
            // Remove the entry.
            if (div)
                div.parentNode.removeChild(div);
        } else if (div) {
            // Update an existing entry.
            div.children[1].innerHTML = summary;
        } else {
            // Create a new entry.
            div = document.createElement('div');
            div.id = div_id;
            div.onclick = function () { sendInput(`quest info ${name}`); };

            var name_div = document.createElement('div');
            name_div.innerHTML = `${name} (level ${level})`;
            div.appendChild(name_div);

            var summary_div = document.createElement('div');
            summary_div.innerHTML = summary;
            div.appendChild(summary_div);

            quests_pane.insertBefore(div, quests_pane.firstChild);
        }
    }
}

MessageHandler.prototype.updateAttributes = function(values) {
    for (var key in values) {
        var div = document.getElementById(key);
        if (div)
            div.innerHTML = values[key];
    }
}

MessageHandler.prototype.startPlayerCast = function(duration) {
    var castbar = document.getElementById("castbar");
    var progress = castbar.children[0];

    castbar.style.display = 'block';
    progress.style.transitionDuration = duration + 's';
    progress.style.width = '0%';

    window.setTimeout(
        function() { progress.style.width = '100%'; },
        0);
}

MessageHandler.prototype.stopPlayerCast = function() {
    var castbar = document.getElementById("castbar");
    castbar.style.display = 'none';
}

function getNeighborId(key) {
    return 'neighbor_' + key;
}

function removeNeighborHighlight(key) {
    var element = document.getElementById(getNeighborId(key));
    if (element) {
        var portrait = element.children[0];
        portrait.className = portrait.className.split(' ').filter(
            function (c) { return !c.startsWith('highlight_'); }).join(' ');
    }
}

function setNeighborHighlight(key, type) {
    var element = document.getElementById(getNeighborId(key));
    if (element) {
        var portrait = element.children[0];
        var classes = portrait.className.split(' ').filter(
            function (c) { return !c.startsWith('highlight_'); });
        classes.push('highlight_' + type);
        portrait.className = classes.join(' ');
    }
}

MessageHandler.prototype.setNeighborProperties = function(item, new_properties) {
    var key = new_properties.key;

    var old_properties = this.neighbors[new_properties.key];
    var properties = old_properties ?
        Object.assign({}, old_properties, new_properties) :
        new_properties;
    this.neighbors[key] = properties;

    if (properties.icon)
        setIcon(item.children[0], "neighbor", properties.icon);

    if (properties.brief)
        item.children[1].children[0].innerHTML = properties.brief;

    if (properties.health && properties.max_health) {
        item.children[1].children[1].children[0].style.width =
            (100.0 * properties.health / properties.max_health) + "%";
    } else {
        item.children[1].children[1].style.visibility = 'hidden';
    }

    // Set a command to perform when clicking the item. TODO: make it
    // appropriate, or add a popup with a few options.
    item._command = 'look {0} #{1}'.format(properties.brief, properties.key);
    item.onmousedown = function() { sendInput(this._command); }
}

MessageHandler.prototype.createNeighbor = function(properties) {
    var neighbors = document.getElementById("neighbors");
    var item = neighbors.children[0].cloneNode(true);
    item.id = getNeighborId(properties.key);
    item.className = "neighbor do_enter";
    item.style.display = "flex";
    this.setNeighborProperties(item, properties);
    neighbors.appendChild(item);
    return item;
}

MessageHandler.prototype.setNeighbors = function(new_neighbors) {
    var neighbors = document.getElementById("neighbors");

    // Remove all but the first child, which is the invisible prototype used to
    // instantiate other items.
    while (neighbors.children[0].nextSibling)
        neighbors.removeChild(neighbors.children[0].nextSibling);

    // Add each neighbor.
    if (new_neighbors) {
        for (var i = 0; i < new_neighbors.length; ++i)
            this.createNeighbor(new_neighbors[i]);
    }
}

MessageHandler.prototype.updateNeighbor = function(properties) {
    var item = document.getElementById(getNeighborId(properties.key));
    if (item)
        this.setNeighborProperties(item, properties);
    else
        this.createNeighbor(properties);
}

MessageHandler.prototype.removeNeighbor = function(key) {
    var item = document.getElementById(getNeighborId(key));

    item.addEventListener('animationend', function (event) {
        this.parentNode.removeChild(this);
    });
    item.className = "neighbor";
    window.requestAnimationFrame(function (t) {
        window.requestAnimationFrame(function (t) {
            item.className = "neighbor do_exit";
        });
    });

    delete this.neighbors[key];
}

// Called when an entity `actor` takes another entity `target`, removing it from
// the current location and possibly replacing it with a new entity
// `replacement` (as when taking fewer than an entire stack of items).
MessageHandler.prototype.didTake = function(actor_path, target_path, count, replacement) {
    var target_name = this.neighbors[target_path].brief;

    if (actor_path == this.player_path) {
        var msg = 'You take {0}.'.format(target_name);
    } else {
        var msg = '{0} takes {1}.'.format(
            this.neighbors[actor_path].brief.capitalize(), target_name);
    }
    this.showText(msg);

    if (replacement != undefined)
        this.replaceNeighbor(target_path, replacement);
    else
        this.removeNeighbor(target_path);
}

// Called when an entity `actor` drops another entity `target`, adding it to the
// current location and possibly replacing a previous entity `replace_path` (as
// adding to a stack of items).
MessageHandler.prototype.didDrop = function(actor_path, target, count, replace_path) {
    if (actor_path == this.player_path) {
        var msg = 'You drop {0}.'.format(target.brief);
    } else {
        var msg = '{0} takes {1}.'.format(
            this.neighbors[actor_path].brief.capitalize(), target.brief);
    }
    this.showText(msg);

    if (replace_path != undefined)
        this.replaceNeighbor(replace_path, target.id);
    else
        this.addNeighbor(target);
}

// Called when an entity `actor` gives the player an entity representing `count`
// items described by `brief`.
MessageHandler.prototype.didGive = function(actor_path, count, brief) {
    var actor_brief = this.neighbors[actor_path].brief.capitalize();

    var item;
    if (count == 1)
        item = brief;
    else
        item = makePlural(brief, count);

    var msg = '{0} gives you {1}.'.format(actor_brief, look(item));
    this.showText(msg);
}

MessageHandler.prototype.formatEmote = function(key, brief, pose) {
    var s = '{0} {1}'.format(look(brief.capitalize()), pose);
    if (this.debug)
        s += ' (#{0})'.format(key);
    return makeTextElement('p', s);
}

MessageHandler.prototype.showEmote = function(path, count, brief, pose) {
    appendBlock(wrapElements('div', [this.formatEmote(path, count, brief, pose)]));
}

MessageHandler.prototype.showHelp = function(text) {
    this.showText(text, 'help');
}

MessageHandler.prototype.showLinks = function(heading, prefix, topics) {
    var elements = [];

    elements.push(makeTextElement('p', heading));
    elements.push(wrapElements('p', topics.map(function (topic) {
        var link = makeTextElement('span', topic,
                                   'link list' + (prefix.startsWith('help') ? ' help' : ''));
        link.onclick = function() { sendInput(prefix + ' ' + topic); };
        return link;
    })));

    appendBlock(wrapElements('div', elements, 'help'));
}

MessageHandler.prototype.showVendorItems = function(heading, vendor, verb, items) {
    var header = makeTextElement('div', heading);

    var entries = [header];
    for (const [brief, price, icon] of items) {

        var div = document.createElement('div');
        div.className = "vendor_item";

        var icon_div = document.createElement('div');
        setIcon(icon_div, "inventory", icon);
        div.appendChild(icon_div);

        const buy_link = link(brief, 'buy', 'buy $ from {0}'.format(vendor));
        var label_div = makeTextElement('div', `${buy_link} --- ${price}`);
        div.appendChild(label_div);

        entries.push(div);
    }

    appendBlock(wrapElements('div', entries));
}

MessageHandler.prototype.showTrainerSkills = function(heading, trainer, skills) {
    var header = makeTextElement('div', heading);

    var entries = [];
    for (const [name, summary, price, karma, known] of skills) {
        const learn_link = link(name, 'learn', 'learn $'.format(trainer));

        var s = `${learn_link} --- ${summary}`;

        if (price !== null && (karma > 0))
            s = s.concat(` Costs ${karma} karma and ${price}.`);
        else if (price !== null)
            s = s.concat(` Costs ${price}.`);
        else if (karma > 0)
            s = s.concat(` Costs ${karma} karma.`);

        if (known)
            s = s.concat(' (already known)');

        var div = makeTextElement('li', s);
        entries.push(div);
    }
    var ul = wrapElements('ul', entries);

    appendBlock(wrapElements('div', [header, ul]));
}

MessageHandler.prototype.showLocation = function(name, description, exits, contents) {
    var elements = [];

    if (name != null)
        elements.push(makeTextElement('h1', name));

    if (description != null)
        elements.push(...formatText(description));

    if (exits != null) {
        var exit_links = [makeTextElement('span', 'Exits:')].concat(
            exits.map(function (dir) {
                var link = makeTextElement('span', dir, 'link list');
                link.onclick = function() { sendInput(dir); };
                return link;
            }));
        elements.push(wrapElements('p', exit_links));
    }

    if (contents != null) {
        for (var i = 0; i < contents.length; ++i) {
            var [key, brief, pose] = contents[i];
            elements.push(this.formatEmote(key, brief, pose));
        }
    }

    appendBlock(wrapElements('div', elements));
}

MessageHandler.prototype.showList = function(header, items) {
    appendBlock(wrapElements('div', [makeTextElement('p', header), makeList(items)]));
}

// Sets the current default target for attacks.
MessageHandler.prototype.setEnemyTarget = function(path) {
    var properties = this.neighbors[path];

    // If there is a current target, change its highlight to be an enemy but not
    // the current target.
    if (this.enemy_target)
        setNeighborHighlight(this.enemy_target, 'enemy');

    this.enemy_target = path;
    setNeighborHighlight(this.enemy_target, 'enemy_target');
    this.showText('You begin attacking {0}.'.format(look(properties.brief)));
    this.enemies.add(path);
}

MessageHandler.prototype.clearEnemyTarget = function() {
    if (this.enemy_target)
        setNeighborHighlight(this.enemy_target, 'hostile');
    this.enemy_target = undefined;
}

// Removes the entity from all target sets.
MessageHandler.prototype.removeTarget = function(id) {
    this.enemies.delete(id);
    removeNeighborHighlight(id);
}

MessageHandler.prototype.showSay = function(speaker, verb, text, is_chat) {
    var elements = [];
    if (text.indexOf("\n\n") == -1) {
        var msg = speaker + " " + verb + ", &ldquo;" + text + "&rdquo;";
        elements.push(makeTextElement('p', msg));
    } else {
        elements.push(makeTextElement('p', speaker + " " + verb + ':'));
        elements = elements.concat(formatText(text, 'blockquote'));
    }
    appendBlock(wrapElements('div', elements), is_chat ? 'chat_text' : 'main_text');
}

MessageHandler.prototype.showChat = function(channel, speaker, text) {
    var message;
    if (speaker)
        message = '[{0}] {1} says, &ldquo;{2}&rdquo;'.format(channel, speaker, text);
    else
        message = '[{0}] {1}'.format(channel, text);

    appendBlock(wrapElements('div', [makeTextElement('p', message)]), 'chat_pane');
}

MessageHandler.prototype.listMacros = function(macros) {
    var elements = [];
    if (macros.length) {
        elements.push(makeTextElement('p', 'You have defined the following macros:'));
        elements.push(makeList(
            macros.map(function (macro) {
                var [name, command] = macro;
                return '{0}: {1}'.format(link(name), command);
            })));
    } else {
        elements.push(makeTextElement('p', "You haven't defined any macros."));
    }
    appendBlock(wrapElements('div', elements));
}

// A message received when one entity damages another entity.
MessageHandler.prototype.didAttack = function(actor, verb, amount, target, health, max_health) {
    var actor_brief =
        (actor == this.player_path) ? 'You' : this.neighbors[actor].brief.capitalize();
    var target_brief =
        (target == this.player_path) ? 'you' : this.neighbors[target].brief;

    if  (actor == this.player_path)
        verb = makeVerbPlural(verb);

    var msg = '{0} {1} {2} for {3} damage!'.format(actor_brief, verb, target_brief, amount);
    this.showText(msg);

    if (target == this.player_path) {
        this.player_stats.health = health;
        this.player_stats.max_health = max_health;
        updateBar('player_health', health, max_health);
    } else {
        this.updateNeighbor({'path': target, 'health': health, 'max_health': max_health});
    }
}

// A message received when one entity kills another, and the victim is
// optionally replaced by a corpse.
MessageHandler.prototype.didKill = function(actor, target, corpse_properties) {
    this.removeTarget(target);

    var actor_brief =
        (actor == this.player_path) ? 'You' : this.neighbors[actor].brief.capitalize();
    var target_brief =
        (target == this.player_path) ? 'you' : this.neighbors[target].brief;

    var msg = '{0} killed {1}!'.format(actor_brief, target_brief);
    this.showText(msg);

    this.replaceNeighbor(target, corpse_properties);
}

MessageHandler.prototype.quit = function() {
    sendInput("quit");
}

MessageHandler.prototype.echoCommand = function(msg) {
    console.log(msg);
    this.showText('&raquo; ' + msg, 'cmd');
}

function sendInput(s) {
    s = s.trim();
    if (s.length) {
        handler.echoCommand(s);
        sendMessage(s);
    }
}

function onUserInput(event) {
    var obj = document.getElementById("command");
    command_history[command_pos] = obj.value;
    if (event.key == "Escape") {
        document.activeElement.blur();
    } else if (event.key == "Enter") {
        if (obj.value.length > 0)
            sendInput(obj.value);
        obj.value = "";
        command_pos = (command_pos + 1) % command_history.length;
    } else if (event.key == "ArrowUp" || event.key == "ArrowDown") {
        var offset = (event.key == "ArrowUp" ? (command_history.length - 1) : 1);
        var new_pos = (command_pos + offset) % command_history.length;
        if (command_history[new_pos] != undefined) {
            obj.value = command_history[new_pos];
            command_pos = new_pos;
        }
    } else if (event.shiftKey && (event.key == "PageUp" || event.key == "PageDown")) {
        handler.cyclePane(event.key == "PageUp" ? 1 : -1);
    }
}

const keyCommands = {
    "w": "go north",
    "a": "go west",
    "s": "go south",
    "d": "go east",
    "r": "go up",
    "f": "go down",
    "i": "go in",
    "o": "go out",
};

window.onkeydown = function (e) {
    var input = document.getElementById("command");
    if (document.activeElement != input) {
        if (e.key == "Enter") {
            input.focus();
            return false;
        } else {
            const command = keyCommands[e.key];
            if (command) {
                sendInput(command);
                return false;
            }
        }
    }
}

function openSession(event) {
    // Nothing to do.
}

function closeSession() {
    handler.showText(
        'The server closed the connection. Please [return to the home page](index.html).',
        'error');
}

function sendMessage(msg) {
    ws.send(msg);
}

function receiveMessage(event) {
    console.log(event.data);
    var message = JSON.parse(event.data);
    handler[message["fn"]].apply(handler, message["args"]);
}

function start() {
    map = new Map(document.getElementById("map_canvas"));
    map.resize();

    handler = new MessageHandler();

    ws = new WebSocket('ws://' + location.host + '/game/session')
    ws.onopen = openSession;
    ws.onclose = closeSession;
    ws.onmessage = receiveMessage;

    var input = document.getElementById("command");
    input.focus();
    input.addEventListener("keydown", (event) => {
        onUserInput(event);
    });
}

document.addEventListener("DOMContentLoaded", function() { setTimeout(start, 0); });
