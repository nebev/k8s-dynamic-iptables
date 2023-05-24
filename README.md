# k8s Dynamic IPTables

This is a small container image which allows you to define outbound and inbound connections via domains, rather than by IP addresses (as you would with say a NetworkPolicy).

The main reason you might want to do this is because you might not know all the IP addresses or ranges of one or more DNS addresses that your container should talk to, or you don't feel like maintaining a list of these in a NetworkPolicy, and don't feel like deploying a Service Mesh for whatever reason.

It's particularly useful for whitelisting egress connectivity by domain, rather than by IP.

## How does it work

This works as an `initContainer` and sets `iptables` rules for you. See [IPTables in Istio](https://github.com/istio/istio/wiki/Understanding-IPTables-snapshot) for more information on how this works.

The container accepts the following arguments:

- `hosts_csv` (required) - This represents the _outbound_ hosts you'd like to whitelist, separated by commas
- `listening_ports_csv` - This represents the _inbound_ ports you'd like to allow.
- `extra_whitelist_ips_csv` - This is a simple list of extra IP(range)-based whitelists you'd like.

With the `hosts_csv` list of hosts, the container will look up the IPs using `dig` and put them into your whitelist.

### Risks

This is a very simple (stupid) DNS lookup with IPTables. Some (but not all) ways this could go wrong include:

- DNS poisoning
- Having your main container run as root or as privileged (which can overwrite the rules set)
- IP Addresses changing during the lifecycle of the pod

If you can, you really should look at NetworkPolicy definitions instead of doing this.

## Example

In this example, we define a regular deployment (`curl`) which simply has an initContainer with this image.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: curl-deployment
  namespace: test
  labels:
    app: curl
spec:
  replicas: 1
  selector:
    matchLabels:
      app: curl
  template:
    metadata:
      namespace: test
      labels:
        app: curl
    spec:
      containers:
      # The Application we want to run
      - name: curl
        image: alpine/curl
        command: ["/bin/sh"]
        args: ["-c", "sleep infinity"]
        ports:
        - containerPort: 3000

      # InitContainers initialise IP Tables to redirect traffic to Envoy
      initContainers:
        image: nebev/k8s-dynamic-iptables:latest # init container
        name: iptables-init
        env:
        - name: hosts_csv
          value: "svc.cluster.local,cluster.local,dl-cdn.alpinelinux.org,deb.debian.org,googleapis.com,storage.googleapis.com"
        - name: listening_ports_csv
          value: "3000"
        - name: extra_whitelist_ips_csv
          value "192.168.0.0/24"
        securityContext:
          capabilities:
            add:
            - NET_ADMIN # Otherwise we can't update iptables
```

If we shell into the container, and run some commands:

```
/ #: curl https://google.com

<TIMES OUT> ^C

/ #: curl https://googleapis.com
<!DOCTYPE html>
<html lang=en>
...
```

We can see that one resolved, and the other didn't, as per our spec.
