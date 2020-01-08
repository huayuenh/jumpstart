const request = require('request');
const parse_link_header = require('parse-link-header');
const argv = require('yargs')
    .usage('Usage: $0 [options]')
    .option('t', {
        alias: 'token',
        describe: 'the OAuth token to invoke github api',
        type: 'string'
    })
    .option('u', {
        alias: 'url',
        describe: 'the base github api URL',
        default: 'https://api.github.com',
        type: 'string'
    })
    .option('o', {
        alias: 'owner',
        describe: 'the owner of github repository',
        type: 'string'
    })
    .option('r', {
        alias: 'repository',
        array: true,
        describe: 'github repositories to search pull requests',
        type: 'string'
    })
    .option('v', {
        alias: 'verbose',
        describe: 'Add verbose logs'
    })
    .demandOption(['o', 'r'])
    .argv;

var options = {
    headers: {
        'Accept': 'application/vnd.github.preview',
        'User-Agent': 'PR-searches'
    },
    json: true
}
if (argv.t) {
    options.headers.Authorization = "token " + argv.t;
}

const baseRequest = request.defaults(options);

var logRateLimit = function (response) {
    console.log(argv.u + " 's rate limit is " + response.headers['x-ratelimit-limit']);
    console.log("Remaining hit(s) for " + argv.u + " is " + response.headers['x-ratelimit-remaining'] + " until " + new Date(response.headers['x-ratelimit-reset'] * 1000));
};

var processPullRequests = function (pullRequests) {
    pullRequests.forEach(aPullRequest => {
        if (aPullRequest.head.repo) {
            console.log(aPullRequest.html_url + ": head: " + aPullRequest.head.repo.html_url + ", state: " + aPullRequest.state + ", fork: " + aPullRequest.head.repo.fork);
        } else {
            // head repository has been deleted - we are assuming that the PR was made out of a fork
            console.log(aPullRequest.html_url + ": head: deleted repository " + aPullRequest.head.label + ", state: " + aPullRequest.state + ", fork: true");
        }
    });
};

function getElements(url, options, processElements) {
    return new Promise(function (resolve, reject) {
        baseRequest.get(url, options, function (error, response, elements) {
            if (error) {
                reject(error);
            }
            if (argv.v) {
                logRateLimit(response);
                console.log("Processing returned elements for HTTP GET " + url);
            }
            processElements(elements);
            let result = { elements: elements };
            if (response.headers.link) {
                var parsedLinkHeader = parse_link_header(response.headers.link);
                if (parsedLinkHeader.next) {
                    result.next = parsedLinkHeader.next.url;
                }
            }
            resolve(result);
        });
    })
};

function resolveAllElements_(result, options, processElements) {
    let promises = [];
    result.elements.forEach(anElement => {
        promises.push(anElement);
    });
    if (result.next) {
        promises.push(getElements(result.next, options, processElements)
            .then(function (nextResult) {
                return resolveAllElements_(nextResult, options, processElements);
            })
        );
    }
    return Promise.all(promises);
};

function flatten(list) {
    return Array.isArray(list) ? list.reduce((a, b) => a.concat(flatten(b)), []) : list;
}

function listAllElements(url, options, processElements) {
    return getElements(url, options, processElements)
        .then(function (result) {
            return resolveAllElements_(result, options, processElements);
        })
        .then(function (allElements) {
            return flatten(allElements);
        });
};

// iterate and reduce the repositories to chain promise
argv.r.reduce(function (previousPromise, repository) {
    return previousPromise.then(function () {
        return listAllElements(argv.u + "/repos/" + argv.o + "/" + repository + "/pulls", { qs: { state: 'all', 'per_page': 100 } }, processPullRequests);
    })
}, Promise.resolve());