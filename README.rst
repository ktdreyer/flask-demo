Testing running Flask apps in OpenShift

Prerequsites
============

Set up Code Ready Containers (I'm using 1.23.1). Follow the instructions for
"Setting up CodeReady Containers on a remote server" (basically: firewall,
HAProxy, dnsmasq wildcard)

Create the New Project
----------------------

After CRC starts, follow the instructions to log in as a developer::

  eval $(crc oc-env)
  oc login -u developer https://api.crc.testing:6443

And create a new project::

  oc new-project flask-demo

Create the BuildConfig and ImageStream
--------------------------------------

This tells OpenShift `how to build the container image <https://docs.openshift.com/container-platform/4.7/cicd/builds/understanding-buildconfigs.html>`_::

    oc create -f buildconfig.yml

This tells OpenShift `how to store the image <https://docs.openshift.com/container-platform/4.7/openshift_images/images-understand.html#images-imagestream-use_images-understand>`_ that we're going to build::

    oc create -f imagestream.yml

Build the image
---------------

Start the first `build
<https://docs.openshift.com/container-platform/4.7/cicd/builds/basic-build-operations.html>`_
for this image::

    oc start-build flask-demo --follow

Troubleshooting
~~~~~~~~~~~~~~~

When I first ran ``start-build``, I did not create the ``ImageStream`` first.
My build was in "New" state for a while, and ``oc logs build/flask-demo-1``
simply timed out because it was waiting for the build to transition out of "New" state ("``timed out waiting for the condition``").

Helpful commands::

    oc logs build/flask-demo-1
    oc get builds

The build should complete in 1.5 minutes.


Deploying the application
-------------------------

Create the `DeploymentConfig
<https://docs.openshift.com/container-platform/4.7/applications/deployments/what-deployments-are.html>`_::

    oc create -f deploymentconfig.yml

Creating a DeploymentConfig will automatically start a pod with the application.
View it with the ``oc get pods`` command::

    oc get pods

    NAME                  READY   STATUS      RESTARTS   AGE
    flask-demo-1-build    0/1     Completed   0          39m
    flask-demo-1-deploy   0/1     Completed   0          4m6s
    flask-demo-1-wr94z    1/1     Running     0          3m59s

Next, we need to define a "Service" for this application::

    oc create -f service.yml

View the new service with::

    oc get svc
    NAME         TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)    AGE
    flask-demo   ClusterIP   172.25.20.203   <none>        5000/TCP   13s

Now we need to expose this service. ``oc expose`` will only create the
plaintext HTTP route, so we use the ``oc create route edge`` command instead::

    oc create route edge flask-demo --service=flask-demo --insecure-policy=Allow

Explaining a few of these settings:

* ``edge`` means "terminate the TLS connection on the 'edge' router (an
  internal haproxy instance) and pass the client's request back to the service
  pod on an unencrypted connection".

* ``--insecure-policy`` tells the router what to do with unencrypted
  (plaintext HTTP) connections. The default behavior (or
  ``--insecure-policy=None``) is to deny plaintext HTTP requests with a HTTP
  503 Service Unavailable message. ``--insecure-policy=Allow`` passes the
  requests through to the application. ``--insecure-policy=Redirect`` sends an
  HTTP 302 Found redirect to the secure TLS port instead.

To see the new route::

    oc get routes
    NAME         HOST/PORT                                PATH   SERVICES     PORT   TERMINATION   WILDCARD
    flask-demo   flask-demo-flask-demo.apps-crc.testing          flask-demo   web    edge          None

Note the "termination" field indicates that this supports HTTPS. A blank
"Termination" field means that this is only exposed over HTTP (not HTTPS).

Now we can load the Flask application::

    curl -k -v https://flask-demo-flask-demo.apps-crc.testing/

To view the Flask app logs (Flask writes to STDOUT)::

    oc logs flask-demo-1-wr94z
     * Running on http://0.0.0.0:5000/ (Press CTRL+C to quit)
     * Restarting with stat
     * Debugger is active!
     * Debugger PIN: 306-896-608
    10.217.0.1 - - [19/Mar/2021 22:56:30] "GET / HTTP/1.1" 200 -

Storage
-------

CRC comes with 30 pre-defined persistent volumes. To examine these, log in as
the cluster administrator::

    oc login -u kubeadmin
    Authentication required for https://api.crc.testing:6443 (openshift)
    Username: kubeadmin
    Password:
    Login successful.

To list all 30 volumes::

    oc get pv

To look at the details of one volume::

    oc describe pv pv0002
    ...
    Source:
      Type:          HostPath (bare host directory volume)
      Path:          /mnt/pv-data/pv0002

Switch back to the developer account when you're done::

    eval $(crc oc-env)
    oc login -u developer https://api.crc.testing:6443
