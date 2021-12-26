wrk-utils: wrk cluster and stats
================================
wrk-utils is a set of commands and `wrk <https://github.com/wg/wrk>`_ lua `scripts <https://github.com/wg/wrk/blob/master/SCRIPTING>`_ to run wrk in **clusters** and **have stats**.

This project consisted of two major parts;

**Commands**, that you can enable and find the help message by sourcing activate script.

**stats.lua**, that collects stats. You can use ``stats.lua`` as the main script or a library.


Features
--------
* Running wrk in clusters using SSH
* Live stats in JSON format, separated by status codes
* Possibility to use ``stats.lua`` as a library to have stats in custom scripts
* Live 5xx status report
* Slack integration
* JSON formatted logs for both requests and responses in files
* Commands to Initialize servers and update files
* Commands to execute and stop wrk
* Execute custom commands on servers
* Read IPs from file or stdin (pipe)
* Debug mode

Final stats sample data:

.. code:: json

    {
        "event": "done",
        "start_time": 1639990232,
        "node": "10.10.1.1",
        "target_url": "https://example.com/list?limit=100",
        "total_completed_requests": 778511,
        "total_sent_requests": 778707,
        "total_timeouts": 2809,
        "connect_error": 0,
        "socket_status_error": 341,
        "read_error": 0,
        "write_error": 0,
        "duration": "484.686049",
        "rps": 1606.22,
        "recv_bytes": "690.31mb",
        "status": {
            "502": 315,
            "200": 778170,
            "504": 26
        }
    }


Live stats sample data:

.. code:: json

    {"event": "response", "node": "10.0.1.2", "thread_id": 1001, "count": 231, "status": {"200": 231}}
    {"event": "response", "node": "10.0.1.2", "thread_id": 1000, "count": 234, "status": {"200": 234}}
    {"event": "response", "node": "10.0.1.2", "thread_id": 1004, "count": 234, "status": {"200": 234}}
    {"event": "response", "node": "10.0.1.3", "thread_id": 1004, "count": 353, "status": {"200": 353}}
    {"event": "response", "node": "10.0.1.3", "thread_id": 1000, "count": 354, "status": {"200": 354}}
    {"event": "response", "node": "10.0.1.2", "thread_id": 1003, "count": 360, "status": {"200": 360}}
    {"event": "response", "node": "10.0.1.2", "thread_id": 1002, "count": 355, "status": {"200": 355}}
    {"event": "response", "node": "10.0.1.3", "thread_id": 1001, "count": 351, "status": {"200": 351, "502": 3}}
    {"event": "response", "node": "10.0.1.3", "thread_id": 1003, "count": 360, "status": {"200": 370}}
    {"event": "response", "node": "10.0.1.3", "thread_id": 1002, "count": 355, "status": {"200": 373}}



Installation & run
------------
#. wrk-utils requires ``sshpass``. Make sure it's installed.
#. Prepare a set of servers with ssh keys OR same ssh username/passwords and provide list of IPs in ``servers.txt`` or pipe addresses to commands.
#. Add ``SSH_USR="<SSH USERNAME>"``, ``SSH_PWD="<SSH PASSWORD>"`` and ``SLACK_WEBHOOK="<SLACK WEBHOOK URL>"`` to ``config.env``. Look at ``config.env.sample``.
#. Run ``. activate.sh`` in bash or ``. activate.fish`` in fish.
#. Now you see can help message and use commands.
#. Run ``init-servers`` command to setup wrk on provided servers by copying wrk binary and lua scripts there. (There is a compiled version of wrk in this repository. You can replace it with another one.)
#. You can run ``sync.file wordlist.txt *.csv`` to copy any other file you need to servers.
#. Run ``available-node-count`` to make sure that all of your servers are ready.
#. Run ``exec-wrk 0 -t10 -c300 -d600s -s stats.lua 'https://example.com/'``
#. You can kill wrk instances using ``kill-all`` command.

.. code:: bash

        # 10 is the delay to execute next wrk instances.
        # All other params after 10 will pass to wrk on servers.
	exec-wrk 10 -t10 -c300 -d600s -s stats.lua 'https://example.com/path/?id=1'

        # running all wrk instances at once by setting delay to zero
	exec-wrk 0 -t10 -c300 -d600s -s custom.lua 'https://example.com/'

Custom script development with stats
------------------------------------

You can use ``stats.lua`` as a library to enable stats for your custom scripts is this way:

.. code:: lua

    require('stats') -- load stats.lua into your custom script

    function request()

        -- you can add request_logger to the request function
        request_logger(false)

        -- ...

        return wrk.format(nil, '/')

    end

    function response(status, headers, body)

        -- you need to add response_logger to the response function
        response_logger(status, headers)
        --  ...
    end


Checkout `examples <examples>`_

Commands
-------------

**ssh-all**: executes a command on all servers

.. code:: bash

    ssh-all 'ps aux | grep something'

**ssh-one**: executes a command on a random server

.. code:: bash

    ssh-one 'ps aux | grep something'

**ssh-all-sudo**: executes a command on all servers as sudo

.. code:: bash

    ssh-all-sudo id | wc

**ssh-one-sudo**: executes a command on a server as sudo

.. code:: bash

    ssh-one-sudo id | wc

**kill-all**: kills all wrk instances on all servers (friendly)

.. code:: bash

    kill-all

**kill-all-force**: kills all wrk instances on all servers (force, will lose logs)

.. code:: bash

    kill-all-force

**available-node-count**: prints number of available servers

.. code:: bash

    available-node-count

**active-node-count**: prints number of active wrk instances in a loop

.. code:: bash

    active-node-count

**live-stats**: live stats for all servers (per thread)

.. code:: bash

    live-stats

**init-servers**: creates wrk directory on servers copies wrk and lua scripts into that

.. code:: bash

    init-servers

**sync-file**: copies provided files to wrk directory on all servers

.. code:: bash

    sync-file wordlist.txt *.jpg

**exec-wrk**: executes wrk step by step or at once (first argument is the delay to execute next instance)

.. code:: bash

    exec-wrk 10 -t10 -c300 -d600s -s stats.lua 'https://example.com/path/?id=1'

.. code:: bash

    exec-wrk 0 -t10 -c300 -d600s -s custom.lua 'https://example.com/'


Known issues
------------
* If you want to pass a URL with multiple parameters to ``wrk-exec``, you need to quote that URL twice. e.g. ``exec-wrk 0 -t1 -c3 -d6s -s stats.lua "'https://example.com/?a=1&b=2'"``
* You need to rerun ``live-stats`` when a new node comes up.
* ``stats.lua`` consider requests with HTTP pipelines as one request. You need to multiply number of requests with number of requests in each pipeline.

TODO
----
* A dashboard to collect logs
* Some documentations
* More examples
* Improve live stats
