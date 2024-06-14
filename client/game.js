'use strict';

function removeAllChildren(node) {
  while (node.firstChild)
    node.removeChild(node.lastChild);
}

function createDiv(id, num_children) {
  let div = document.createElement("div");
  div.id = id;
  for (let i = 0; i < num_children; ++i)
    div.appendChild(document.createElement("div"));
  return div;
}

function link(text, type = "", command = "") {
  return `\`${type}:${text}:${command}\``;
}

function look(s) {
  return link(s, "look", "look at $");
}

// Sets the class name of an element to match that defined in the CSS for the specified icon.
function setIcon(element, type, icon) {
  if (icon)
    element.className = `${type}_icons ${type}_${icon}`;
}

// Updates a stat bar to reflect a current and maximum value.
function updateBar(id, current, max) {
  let p = max ? Math.min(100, 100.0 * current / max) : 0;
  let bar = document.getElementById(id);
  bar.children[0].style.width = p + "%";
  bar.children[1].innerHTML = current + " / " + max;
}

// Panes in left-to-right order.
const panes = ["inventory", "equipment", "combat", "skills", "quests", "chat"];

class GameClient {
  currentPane = "inventory";
  commandHistory = new Array(100);
  commandPos = 0;
  avatarKey = null;
  debug = true;

  constructor() {
    this.map = new Map(document.getElementById("map_canvas"));
    this.map.resize();

    let self = this;
    this.ws = new WebSocket('ws://' + location.host + '/game/session')
    this.ws.onopen = (event) => { self.openSession(event); }
    this.ws.onclose = () => { self.closeSession(); }
    this.ws.onmessage = (event) => { self.receiveMessage(event); }
  }

  openSession(event) {
    // Nothing to do.
  }

  closeSession() {
    this.appendTextBlock(
                         "The server closed the connection. Please [return to the home page](index.html).",
                         "error");
  }

  receiveMessage(event) {
    console.log(event.data);
    const message = JSON.parse(event.data);
    for (const update of message.updates) {
      // Each update is a map with one entry. The key is the name of the method to call
      // and the value is its single argument.
      const [key, value] = Object.entries(update)[0];
      const fn = this[key];
      if (fn)
        fn.call(this, value);
      else
        console.log(`ignoring update with unknown type: ${key}`);
    }
  }

  sendMessage(msg) {
    this.ws.send(msg);
  }

  sendInput(s) {
    s = s.trim();
    if (s.length) {
      this.echoCommand(s);
      this.sendMessage(s);
    }
  }

  resize() {
    this.map.resize();
  }

  showPane(button_id) {
    document.getElementById(this.currentPane).className = "button toggle_off";
    document.getElementById(this.currentPane + "_pane").style.display = "none";

    this.currentPane = button_id;

    document.getElementById(this.currentPane).className = "button toggle_on";
    document.getElementById(this.currentPane + "_pane").style.display = "block";
  }

  cyclePane(dir) {
    let curr = this.currentPane;
    let i = panes.findIndex((x) => (x == curr));
    if (dir == 1)
      i = (i + 1) % panes.length;
    else
      i = (i + panes.length - 1) % panes.length;
    this.showPane(panes[i]);
  }

  quit() {
    this.sendInput("quit");
  }

  // MARK: Messages

  // Appends a block element to a scrollable text pane, removing the oldest block
  // first if the maximum number of blocks would be exceeded.
  appendBlock(block, containerId = "main_text") {
    const MAX_BLOCKS = 500;
    let container = document.getElementById(containerId);
    if (container.childNodes.length >= MAX_BLOCKS)
      container.removeChild(container.firstChild);
    container.appendChild(block);
    container.scrollTop = container.scrollHeight;
  }

  appendTextBlock(text, className) {
    this.appendBlock(wrapElements("div", formatText(text), className));
  }

  echoCommand(msg) {
    console.log(msg);
    this.appendTextBlock(`&raquo; ${msg}`, "cmd");
  }

  showRaw({_0: text}) {
    let element = document.createElement("pre");
    element.innerHTML = text;
    this.appendBlock(element);
  }

  showText({_0: text}) {
    this.appendTextBlock(text);
  }

  showNotice({_0: text}) {
    this.appendTextBlock(text, "notice");
  }

  showTutorial({_0: text}) {
    this.appendTextBlock(text, "tutorial");
  }

  showError({_0: text}) {
    this.appendTextBlock(text, "error");
  }

  showHelp({_0: text}) {
    // TODO: look for links to "see also" topics and format them appropriately.
    this.appendTextBlock(text, "help");
  }

  showList({heading, items}) {
    this.appendBlock(wrapElements("div", [makeTextElement("p", heading), makeList(items)]));
  }

  showSay({speaker, verb, text, isChat}) {
    let elements = [];
    if (text.indexOf("\n\n") == -1) {
      let msg = `${speaker} ${verb}, &ldquo;${text}&rdquo;`;
      elements.push(makeTextElement("p", msg));
    } else {
      elements.push(makeTextElement("p", `${speaker} ${verb}:`));
      elements = elements.concat(formatText(text, "blockquote"));
    }
    this.appendBlock(wrapElements("div", elements), isChat ? 'chat_text' : 'main_text');
  }

  showLinks({heading, prefix, topics}) {
    let elements = [];

    elements.push(makeTextElement("p", heading));
    elements.push(wrapElements("p", topics.map((topic) => {
      var link = makeTextElement("span", topic,
                                 "link list" + (prefix.startsWith("help") ? " help" : ""));
      link.onclick = () => { client.sendInput(prefix + " " + topic); };
      return link;
    })));

    this.appendBlock(wrapElements("div", elements, "help"));
  }

  // MARK: Location

  formatEmote(key, brief, pose) {
    let s = "{0} {1}".format(look(brief.capitalize()), pose);
    if (this.debug)
      s+= ` (#${key})`;
    return makeTextElement("p", s);
  }

  showLocation({name, description, exits, contents}) {
    let elements = [];

    if (name != null)
      elements.push(makeTextElement("h1", name));

    if (description != null)
      elements.push(...formatText(description));

    if (exits != null) {
      let exit_links = [makeTextElement("span", "Exits:")]
      .concat(exits.map((dir) => {
        let link = makeTextElement("span", dir, "link list");
        link.onclick = () => { client.sendInput(dir); };
        return link;
      }));
      elements.push(wrapElements("p", exit_links));
    }

    if (contents != null) {
      for (let {key, brief, pose} of contents)
        elements.push(this.formatEmote(key, brief, pose));
    }

    this.appendBlock(wrapElements("div", elements));
  }

  // MARK: Map

  setMap({region, subregion, location, radius, cells}) {
    const sep = "\u2002\u00b7\u2002";

    document.getElementById("location_name").innerHTML = location;
    if (subregion)
      document.getElementById("zone_name").innerHTML = region + sep + subregion;
    else
      document.getElementById("zone_name").innerHTML = region;

    this.map.update(radius, cells);
    this.map.render();
  }

  updateMap({cells}) {
    // TODO: implement partial map update
  }

  // MARK: Avatar

  setAvatarKey({_0: key}) {
    this.avatarKey = key;
  }

  setAvatarIcon({_0: icon}) {
    if (icon)
      setIcon(document.getElementById("player_icon"), "avatar", icon);
  }

  setAvatarName({_0: name}) {
    if (name) {
      let div = document.getElementById("player_name");
      div.childNodes[0].innerHTML = `${name}, `;
    }
  }

  setAvatarLevel({_0: level}) {
    let div = document.getElementById("player_name");
    div.childNodes[1].innerHTML = `level ${level}`;
  }

  setAvatarRace({_0: race}) {
    let div = document.getElementById("player_name");
    div.childNodes[2].innerHTML = ` ${race}`;
  }

  setAvatarXP({current, max}) {
    updateBar("player_xp", current, max);
  }

  setAvatarHealth({current, max}) {
    updateBar("player_health", current, max);
  }

  setAvatarEnergy({current, max}) {
    updateBar("player_energy", current, max);
  }

  setAvatarMana({current, max}) {
    // updateBar("player_mana", current, max);
  }

  // MARK: Neighbors

  setNeighborProperties(div, {key, brief, icon, currentHealth, maxHealth}) {
    if (icon)
      setIcon(div.children[0], "neighbor", icon);

    if (brief)
      div.children[1].children[0].innerHTML = brief;

    if (currentHealth && maxHealth)
      div.children[1].children[1].children[0].style.width = (100.0 * currentHealth / maxHealth) + "%";
    else
      div.children[1].children[1].style.visibility = "hidden";

    // Set a command to perform when clicking the item.
    // TODO: make it appropriate, or add a popup with a few options.
    div._command = `look ${brief} #${key}`;
    div.onmousedown = function() { client.sendInput(this._command); };
  }

  createNeighbor(neighbor) {
    let key = neighbor["key"];
    let neighbors = document.getElementById("neighbors");
    let div = neighbors.children[0].cloneNode(true);
    div.id = `neighbor_${key}`;
    div.className = "neighbor do_enter";
    div.style.display = "flex";
    neighbors.appendChild(div);
    this.setNeighborProperties(div, neighbor);
    return div;
  }

  clearNeighbors() {
    // Remove all but the first child, which is the invisible prototype used to
    // instantiate other items.
    let neighbors = document.getElementById("neighbors");
    while (neighbors.children[0].nextSibling)
      neighbors.removeChild(neighbors.children[0].nextSibling);
  }

  setNeighbors({_0: neighbors}) {
    this.clearNeighbors();
    for (let neighbor of neighbors)
      this.createNeighbor(neighbor);
  }

  updateNeighbor({_0: neighbor}) {
    let id = `neighbor_${neighbor.key}`;
    let div = document.getElementById(id);
    if (div)
      this.setNeighborProperties(div, neighbor);
    else
      this.createNeighbor(neighbor);
  }

  removeNeighbor({key}) {
    let id = `neighbor_${key}`;
    let div = document.getElementById(id);
    if (div) {
      div.addEventListener('animationend', function (event) { this.parentNode.removeChild(this); });
      div.className = "neighbor";
      window.requestAnimationFrame(function (t) {
        window.requestAnimationFrame(function (t) {
          div.className = "neighbor do_exit";
        });
      });
    }
  }

  // MARK: Inventory

  updateItemElement(div, icon, brief) {
    setIcon(div.children[0], "inventory", icon);
    div.children[1].innerHTML = brief;
  }

  setItems({_0: items}) {
    let contents = document.getElementById("inventory_contents");

    while (contents.firstChild)
      contents.removeChild(contents.firstChild);

    for (const item of items) {
      const {key, icon, brief} = item;

      div = document.createElement('div');
      div.id = `inv_${key}`;
      // FIXME: div.setAttribute("jade_sort_key", sort_key);
      div.appendChild(document.createElement("div"));  // for icon
      div.appendChild(document.createElement("div"));  // for brief

      self.updateItemElement(div, icon, brief);

      // FIXME: contents_div.insertBefore(div, findInventoryDivAfter(sort_key, contents_div.children));
      contents.appendChild(div);
    }
  }

  updateItem({_0: item}) {
    const {key, icon, brief} = item;
    let div = document.getElementById(`inv_${key}`);
    if (div)
      self.updateItemElement(div, icon, brief);
  }

  removeItem({_0: key}) {
    let div = document.getElementById(`inv_${key}`);
    if (div)
      div.parentNode.removeChild(div);
  }

  // MARK: Cast bar

  // TODO: Support neighbor/combatant cast bars.

  startCast({key, duration}) {
    if (key == this.avatarKey) {
      let castbar = document.getElementById("castbar");
      let progress = castbar.children[0];

      castbar.style.display = "block";
      progress.style.transitionDuration = duration + "s";
      progress.style.width = "0%";

      window.setTimeout(function() { progress.style.width = "100%"; }, 0);
    }
  }

  stopCast({key}) {
    if (key == this.avatarKey) {
      let castbar = document.getElementById("castbar");
      castbar.style.display = "none";
    }
  }

  // MARK: Auras

  // TODO: Support neighbor/combatant auras. Handle name and expiry.

  setAuras({key, auras}) {
    for (let aura of auras)
      this.addAura(key, aura);
  }

  addAura({key, aura}) {
    let {type, icon, name, expiry} = aura;
    let id = `aura_${type}`
    let div = document.getElementById(id);
    if (!div) {
      div = document.createElement("div");
      div.id = id;
      div.className = "show_aura";
      document.getElementById("player_auras").insertBefore(div, null);
    }
    setIcon(div, icon);
  }

  removeAura({key, type}) {
    let div = document.getElementById(`aura_${type}`);
    if (div) {
      div.addEventListener("animationend", (event) => {
        this.parentNode.removeChild(this);
      });
      div.className = "hide_aura";
    }
  }

  // MARK: Equipment

  setEquipment({_0: items}) {
    for (let item of items)
      this.equip(item);
  }

  equip({_0: item}) {
    let {slot, icon, brief} = item;
    let div = document.getElementById(`equip_${slot}`);
    if (div) {
      removeAllChildren(div);

      let icon_div = document.createElement("div");
      setIcon(icon_div, "inventory", icon);
      div.appendChild(icon_div);

      let brief_div = document.createElement("div");
      brief_div.innerHTML = brief;
      div.appendChild(brief_div);
    }
  }

  unequip({slot}) {
    let div = document.getElementById(`equip_${slot}`);
    if (div)
      removeAllChildren(div);
  }

  // MARK: Skills

  setKarma({_0: karma}) {
    document.getElementById("unspent_karma").innerHTML = `Unspent karma: ${karma}`;
  }

  setSkills({_0: skills}) {
    for (let skill of skills)
      updateSkill(skill);
  }

  updateSkill({_0: skill}) {
    const {label, name, rank, maxRank} = skill;
    const id = `skill_${label}`;
    let div = document.getElementById(id);
    if (div) {
      div.children[1].innerHTML = `${rank} / ${maxRank}`;
    } else {
      let pane = document.getElementById("skills_pane");

      // Find the existing skill entry before which to insert the new one,
      // based on ordering by skill name. Ignore the first child, which is
      // the unspent karma and not a skill.
      let next_div = null;
      for (let i = 1; i < pane.children.length; ++i) {
        let child = pane.children[i];
        if (name < child.children[0].innerHTML) {
          next_div = child;
          break;
        }
      }

      // Create a new entry.
      div = createDiv(id, 3);
      div.children[0].innerHTML = name;
      div.children[0].onclick = () => { client.sendInput(`skill ${name}`); };
      if (maxRank > 0)
        div.children[1].innerHTML = `${rank} / ${maxRank}`;
      pane.insertBefore(div, next_div);
    }
  }

  removeSkill({_0: label}) {
    const id = `skill_${label}`;
    let div = document.getElementById(id);
    if (div)
      div.parentNode.removeChild(div);
  }

}  // class GameClient

let client = null;

// MARK: Old

/*

function findInventoryDivAfter(sort_key, item_divs) {
  for (const div of item_divs) {
    if (Number(div.getAttribute("wyrm_sort_key")) > sort_key)
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

        contents_div.insertBefore(div, findInventoryDivAfter(sort_key, contents_div.children));
      }
    }
  }
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

function removeNeighborHighlight(key) {
  var element = document.getElementById(getNeighborId(key));
  if (element) {
    var portrait = element.children[0];
    portrait.className = portrait.className.split(' ')
      .filter(function (c) { return !c.startsWith('highlight_'); }).join(' ');
  }
}

function setNeighborHighlight(key, type) {
  var element = document.getElementById(getNeighborId(key));
  if (element) {
    var portrait = element.children[0];
    var classes = portrait.className.split(' ')
      .filter(function (c) { return !c.startsWith('highlight_'); });
    classes.push('highlight_' + type);
    portrait.className = classes.join(' ');
  }
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

MessageHandler.prototype.listMacros = function(macros) {
  var elements = [];
  if (macros.length) {
    elements.push(makeTextElement('p', 'You have defined the following macros:'));
    elements.push(makeList(macros.map(function (macro) {
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

*/

// A history of commands entered by the player.
let command_history = new Array(100);
let command_pos = 0;

function onUserInput(event) {
  var obj = document.getElementById("command");
  command_history[command_pos] = obj.value;
  if (event.key == "Escape") {
    document.activeElement.blur();
  } else if (event.key == "Enter") {
    if (obj.value.length > 0)
      client.sendInput(obj.value);
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
        client.sendInput(command);
        return false;
      }
    }
  }
}

function start() {
  client = new GameClient();

  let input = document.getElementById("command");
  input.focus();
  input.addEventListener("keydown", (event) => { onUserInput(event); });
}

document.addEventListener("DOMContentLoaded", () => { setTimeout(start, 0); });
