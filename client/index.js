String.prototype.strip = function() {
    return this.replace(/^\s+|\s+$/g, '');
}

function setWarning(msg) {
    prompt = document.getElementById("warning");
    prompt.innerHTML = msg;
}

function showLogin() {
    document.getElementById("warning").innerHTML = "";
    document.getElementById("signup").style.display = 'none';
    document.getElementById("login").style.display = 'block';

    var fields = ['luser', 'lpass'];
    fields.map(function(f) { document.getElementById(f).value = ''; });

    document.getElementById("modalmask").style.display = 'block';
    document.getElementById("logindialog").style.display = 'block';
    document.getElementById("luser").focus();
}

function showSignup() {
    document.getElementById("warning").innerHTML = "";
    document.getElementById("login").style.display = 'none';
    document.getElementById("signup").style.display = 'block';

    var fields = ['cuser', 'cpass1', 'cpass2'];
    fields.map(function(f) { document.getElementById(f).value = ''; });

    document.getElementById("modalmask").style.display = 'block';
    document.getElementById("logindialog").style.display = 'block';
    document.getElementById("cuser").focus();
}

function hidePopup() {
    document.getElementById("modalmask").style.display = 'none';
    document.getElementById("logindialog").style.display = 'none';
}

function loginUser(event) {
    event.preventDefault();

    var user = document.getElementById("luser").value;
    var pass = document.getElementById("lpass").value.strip();

    var request = new XMLHttpRequest();
    request.onload = onAuthResponse;
    request.open("GET", "/game/login");
    request.setRequestHeader("Authorization", "Basic " + btoa(user + ':' + pass));
    request.send();
}

function createUser(event) {
    event.preventDefault();

    var user = document.getElementById("cuser").value;
    var pass1 = document.getElementById("cpass1").value.strip();
    var pass2 = document.getElementById("cpass2").value.strip();

    if (/^[\w.,@+-]{3,20}$/.test(user) == false) {
        document.getElementById("cuser").value = "";
        setWarning("Your username must be between 3 and 20 characters long.");
        return;
    }
    else if (pass1 != pass2) {
        document.getElementById("cpass1").value = "";
        document.getElementById("cpass2").value = "";
        setWarning("Passwords do not match.");
        return;
    }
    else if (pass1.length < 8 || pass1.length > 40) {
        document.getElementById("cpass1").value = "";
        document.getElementById("cpass2").value = "";
        setWarning("Passwords must be at between 8 and 40 characters long.",
            true);
        return;
    }

    // Send a request to submit the proposed new user's information
    request = new XMLHttpRequest();
    request.onload = function(event) { onAuthResponse(event, true); }
    request.open("GET", "/game/create");
    request.setRequestHeader("Authorization", "Basic " + btoa(user + ':' + pass1));
    request.send();
}

function play() {
    window.location = 'game.html';
}

function authenticate() {
    var request = new XMLHttpRequest();
    request.onload = onAuthResponse;
    request.open("GET", "/game/auth", true);
    request.send();
}

function onAuthResponse(event, create) {
    var request = event.target;
    var header = document.getElementById("header");
    var action = document.getElementById("actionbox");
    if (request.status == 401) {
        action.className = "loginaction";
        action.innerHTML = "Log in to Play";
        action.onclick = showLogin;
        header.innerHTML =
            'Want to play? <a href="javascript:void(0)" onclick="showLogin()">Log in</a>' +
            ' or <a href="javascript:void(0)" onclick="showSignup()">sign up</a>';
        if (create) {
            setWarning("That username is already in use.");
            document.getElementById("cuser").focus();
        }
        else {
            setWarning("Invalid username or password.", true);
            document.getElementById("lpass").focus();
        }
    }
    else if (request.status == 200) {
        var data = eval('(' + request.response + ')');
        action.className = "playaction";
        action.innerHTML = "Play Now";
        action.onclick = play;
        header.innerHTML =
            'Welcome, ' + data["username"] + '! ' +
            '<a href="javascript:void(0)" onclick="settings()">settings</a> &middot; ' +
            '<a href="javascript:void(0)" onclick="logout()">logout</a>';

        // In case this was a login or create.
        hidePopup();
    }
    else {
        // Should indicate server problem, possibly retry later?
    }
}

function logout() {
    var request = new XMLHttpRequest();
    request.onload = onLogoutResponse;
    request.open("GET", "/game/logout", true);
    request.send();
}

function onLogoutResponse(event) {
    authenticate();
}

function appendColumn(row, content) {
    var col = document.createElement("td");
    col.innerHTML = content;
    row.appendChild(col);
}

function showPlayers() {
    var request = new XMLHttpRequest();
    request.onload = (event) => {
        var request = event.target;
        if (request.status == 200) {
            var players = JSON.parse(request.response);
            players.sort((a, b) => { return a.name < b.name; });

            var table = document.getElementById("player_table");

            var heading = document.createElement("tr");
            appendColumn(heading, "Name");
            appendColumn(heading, "Level");
            appendColumn(heading, "Race");
            appendColumn(heading, "Region");
            table.appendChild(heading);

            for (var i = 0; i < players.length; ++i) {
                var player = players[i];
                var row = document.createElement("tr");
                appendColumn(row, player.name);
                appendColumn(row, player.level);
                appendColumn(row, player.race);
                appendColumn(row, player.region);
                table.appendChild(row);
            }
        }
    };
    request.open("GET", "/game/who", true);
    request.send();
}

function init() {
    document.getElementById("createform").onsubmit = createUser;
    document.getElementById("loginform").onsubmit = loginUser;
    authenticate();

    var id = window.location.pathname.substring(1).split(".")[0];
    var el = document.getElementById(id);
    if (el)
        el.className = "current";

    var sidebox = document.getElementById("sidebox");
    for (var i = 0; i < sidebox.children.length; ++i) {
        var c = sidebox.children[i];
        c.onclick = (function (x) { return () => { window.location = x; }; })(c.id + ".html");
    }
    document.getElementById("players").onclick = (e) => { window.location = "who.html"; };

    var request = new XMLHttpRequest();
    request.onload = (event) => {
        var request = event.target;
        if (request.status == 200) {
            var n = request.getResponseHeader("X-Num-Players");
            var msg = n + (n == 1 ? " player is online" : " players are online");
            document.getElementById("players").innerHTML = msg;
        }
    };
    request.open("HEAD", "/game/who", true);
    request.send();
}

document.addEventListener("DOMContentLoaded", function() { setTimeout(init, 0); });
