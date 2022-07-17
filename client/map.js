'use strict';

// Images used as icons within map cells.
var map_icon_urls = {
    // Location state icons.
    'quest_available': 'icons/quest-available.png',
    'quest_incomplete': 'icons/quest-incomplete.png',
    'quest_complete': 'icons/quest-complete.png',
    'vendor': 'icons/vendor.png',
    'trainer': 'icons/trainer.png',

    // Vehicle and structure icons.
    'boat': 'icons/sinagot.png',
    'house': 'icons/house.png',
    'wagon': 'icons/old-wagon.png',
};

// Styles used to fill the interior of a map cell based on its surface.
var surface_styles = {
    'dirt': 'hsl(30, 20%, 25%)',
    'flowers': 'hsl(330, 50%, 55%)',
    'forest': 'hsl(100, 40%, 40%)',
    'grass': 'hsl(100, 40%, 60%)',
    'weeds': 'hsl(85, 40%, 40%)',
    'stone': 'hsl(0, 0%, 50%)',
    'water': 'hsl(224, 60%, 50%)',
    'wood': 'hsl(20, 28%, 33%)',
    'sand': 'hsl(55, 38%, 53%)',
    'snow': 'hsl(0, 0%, 80%)',
    'tile': 'hsl(330, 18%, 67%)',
};

// Styles used to fill the background of a map cell based on its domain.
var domain_styles = {
    'indoor': 'hsl(0, 0%, 20%)',
    'outdoor': 'hsl(82, 25%, 20%)',
    'underground': 'hsl(28, 25%, 20%)',
};

// Loads a set of images and runs a callback after each one.

function ImageLoader(image_urls)
{
    this.image_urls = image_urls;
    this.images = {};
    this.finish_callback = undefined;
}

ImageLoader.prototype.loadImages = function(callback)
{
    this.callback = callback;

    for (var key in this.image_urls) {
        var url = this.image_urls[key];
        (function (key, url, loader) {
            var image = new Image();
            image.onload = function() { loader.onLoadImage(key, this); }
            image.src = url;
        })(key, url, this);
    }
}

ImageLoader.prototype.onLoadImage = function(key, image)
{
    this.images[key] = image;
    this.callback(this);
}

ImageLoader.prototype.finishedLoading = function()
{
    return Object.keys(this.images).length == Object.keys(this.image_urls).length;
}

// Renders a representation of the rooms around the player.

function Map(canvas)
{
    this.canvas = canvas;
    this.radius = 0;
    this.rooms = undefined;

    var self = this;

    this.icons = undefined;
    var icon_loader = new ImageLoader(map_icon_urls);
    icon_loader.loadImages(function(loader) { self.onLoadIcon(loader); });
}

Map.prototype.onLoadIcon = function(loader)
{
    if (loader.finishedLoading()) {
        this.icons = loader.images;
        this.render();
    }
}

Map.prototype.finishedLoading = function()
{
    return this.icons != undefined;
}

Map.prototype.update = function(radius, rooms)
{
    this.radius = radius;
    this.rooms = rooms;
}

// FIXME: This needs updating.
Map.prototype.showTooltip = function(e)
{
    var cs = Math.min(this.canvas.width, this.canvas.height) / (2 * this.radius + 1);
    var x = e.offsetX / cs;
    var y = e.offsetY / cs;
    var label = "";
    for (var i = 0; i < this.rooms.length; ++i) {
        var r = this.rooms[i];
        if (x >= r.x && x < r.x + 1 && y >= r.y && y < r.y + 1) {
            label = r.name + " " + r.terrain + " " + r.x + " " + r.y;
            break;
        }
    }
}

var exit_lines = [
    [0, -1],
    [1, -1],
    [1, 0],
    [1, 1],
    [0, 1],
    [-1, 1],
    [-1, 0],
    [-1, -1],
];

Map.prototype.resize = function()
{
    this.canvas.width = this.canvas.clientWidth;
    this.canvas.height = this.canvas.clientHeight;
    this.render();
}

function drawExitLines(context, left, top, cell_size, room_size, exits) {
    context.beginPath();
    for (var i = 0; i < 8; ++i) {
        if (exits & (1 << i)) {
            var [lx, ly] = exit_lines[i];
            var sx = cell_size / 2 + room_size / 2 * lx;
            var sy = cell_size / 2 + room_size / 2 * ly;
            var ex = cell_size / 2 * (1 + lx) + lx;
            var ey = cell_size / 2 * (1 + ly) + ly;
            context.moveTo(left + sx, top + sy);
            context.lineTo(left + ex, top + ey);
        }
    }
    context.stroke();
}

Map.prototype.render = function()
{
    if (!this.finishedLoading() || !this.rooms)
        return;

    var context = this.canvas.getContext("2d");
    context.imageSmoothingQuality = "high";
    context.fillStyle = "#2a2a2e";
    context.fillRect(0, 0, this.canvas.width, this.canvas.height);

    // Figure out the size and placement of the map cells. Each cell is square
    // and has a size that is a multiple of four, as this reduces rendering
    // artifacts due to fractional pixel coordinates.
    var map_size = Math.max(this.canvas.width, this.canvas.height);
    var diameter = 2 * this.radius + 1;
    var cell_size = (Math.ceil(map_size / diameter) + 3) & ~3;
    var center_left = Math.floor((this.canvas.width - cell_size) / 2);
    var center_top = Math.floor((this.canvas.height - cell_size) / 2);
    var inset = cell_size / 4;
    var room_size = cell_size - inset * 2;

    for (var j = 0; j < this.rooms.length; ++j) {
        var [id, x, y, name, icon, state, surface, surrounding, domain] = this.rooms[j];

        var left = center_left + x * cell_size, top = center_top + y * cell_size;

        // Fill the cell background.
        var style = surrounding ? surface_styles[surrounding] : domain_styles[domain];
        if (style) {
            context.fillStyle = style;
            context.fillRect(left, top, cell_size, cell_size);
        }

        // For an underground or outdoor room, draw a wider line along each
        // diagonal exit.
        if (domain == 'underground' || domain == 'outdoor') {
            context.strokeStyle = domain_styles[domain];
            context.lineWidth = cell_size / 4;
            context.lineCap = 'butt';
            drawExitLines(context, left, top, cell_size, room_size, state & 0xaa);
        }

        // Render a highlight around the current room.
        if (x == 0 && y == 0) {
            context.lineWidth = 8;
            context.strokeStyle = '#c8c868';
            context.strokeRect(left + inset - 4, top + inset - 4,
                               room_size + 8, room_size + 8);
        }

        // Render the foreground of each room.
        context.lineWidth = 4;
        context.lineCap = 'round';

        // Fill the room interior based on the surface.
        var style = surface_styles[surface];
        if (style) {
            context.fillStyle = style;
            context.fillRect(left + inset, top + inset, room_size, room_size);
        }

        // Draw an icon if one is defined. FIXME:
        if (icon) {
            var image = this.icons[icon];
            if (image) {
                context.drawImage(image, left + inset + 2, top + inset + 2,
                                  room_size - 4, room_size - 4);
            }
        }

        // Draw the room border and lines for exits.
        context.strokeStyle = '#1f1f1f';
        context.strokeRect(left + inset, top + inset, room_size, room_size);
        drawExitLines(context, left, top, cell_size, room_size, state);

        context.fillStyle = '#1f1f1f';
        if (state & (1 << 8)) {
            // Upward-pointing triangle in upper-left corner.
            var l = left + inset + 2, r = left + cell_size / 2 - 2,
                b = top + inset, t = top + inset / 2;
            context.beginPath();
            context.moveTo(l, b);
            context.lineTo(r, b);
            context.lineTo((l + r) / 2, t);
            context.closePath();
            context.fill();
        }
        if (state & (1 << 9)) {
            // Downward-pointing triangle in lower-right corner.
            var l = left + cell_size / 2 + 2, r = left + cell_size - inset - 2,
                t = top + cell_size - inset, b = top + cell_size - inset / 2;
            context.beginPath();
            context.moveTo(l, t);
            context.lineTo((l + r) / 2, b);
            context.lineTo(r, t);
            context.closePath();
            context.fill();
        }

        // Draw a symbol to denote quest state.
        if (state & 0x7000) {
            var m = {0x1000: "quest_available",
                     0x2000: "quest_incomplete",
                     0x4000: "quest_complete"};
            var image = this.icons[m[state & 0x7000]];
            context.drawImage(image, left + inset + 2, top + inset + 2,
                              room_size / 2 - 2, room_size / 2 - 2);
        }

        // Draw a symbol if there's a vendor.
        if (state & 0x8000) {
            var image = this.icons["vendor"];
            context.drawImage(image, left + inset + room_size / 2, top + inset + 2,
                              room_size / 2 - 2, room_size / 2 - 2);
        }

        // Draw a symbol if there's a trainer.
        if (state & 0x10000) {
            var image = this.icons["trainer"];
            context.drawImage(image, left + inset + 2, top + inset + room_size / 2,
                              room_size / 2 - 2, room_size / 2 - 2);
        }
    }
}
