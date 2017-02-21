import getpass
import os
import re
import urllib


try:
    import json
except ImportError:
    import simplejson
    json = simplejson

try:
    import urllib2
except ImportError:
    import urllib.request
    # This usage is generally correct for this script
    urllib2 = urllib.request
have_argparse = True
try:
    import argparse
except ImportError:
    from optparse import OptionParser
    OptionParser.add_argument = OptionParser.add_option
    have_argparse = False
import sys


def main():
    description = 'Helper script that gives you all the access tokens your account has.'
    if have_argparse:
        parser = argparse.ArgumentParser(description=description,
            formatter_class=argparse.ArgumentDefaultsHelpFormatter)
    else:
        parser = OptionParser('%prog [options] user_name', description=description)

    parser.add_argument('--url', default='https://api.signalfx.com/v1', help='SignalFX endpoint')
    parser.add_argument('--password', default=None, help='Optional command line password')
    parser.add_argument('--org', default=None,
                        help='If set, change output to only the auth token of this org')
    parser.add_argument('--print_user_org', default=False, action='store_true',
                        help='If set, change output to only the auth token of this org')
    parser.add_argument('--update', default=None,
                        help='If set, will look for a collectd file and auto update to the auth token you select.')
    parser.add_argument('--print_token_only', default=False, action='store_true',
                        help='If set, only print out tokens')
    parser.add_argument('--error_on_multiple', default=False, action ='store_true',
                        help='If set then an error will be raised if the user is part of multiple organizations '
                             'and --org is not specified')

    if have_argparse:
        parser.add_argument('user_name', help="User name to log in with")
        args = parser.parse_args()
    else:
        (args, leftover) = parser.parse_args()
        if not leftover:
            parser.error("User name to log in with must be specified.")
        if len(leftover) != 1:
            parser.error("Only one user name to log in with must be specified.")
        args.user_name = leftover[0]

    if args.update is not None:
        assert os.path.isfile(args.update), "Unable to find the file to update: " + args.update

    if args.password is None:
        args.password = getpass.getpass('SignalFX password: ')

    # Get the session
    json_payload = {"email": args.user_name, "password": args.password}
    headers = {'content-type': 'application/json'}
    req = urllib2.Request(args.url + "/session", json.dumps(json_payload), headers)
    try:
        resp = urllib2.urlopen(req)
    except urllib2.HTTPError, e:
        if e.code == 201:
            resp = e
        else:
            sys.stderr.write("Invalid user name/password\n")
            sys.exit(1)
    res = resp.read()
    sf_accessToken = json.loads(res)['sf_accessToken']
    sf_userID = json.loads(res)['sf_userID']

    # Get the orgs
    orgs_url = args.url + "/organization?query=sf_organization:%s" % (urllib.quote(args.org or '*'))
    headers = {'content-type': 'application/json', 'X-SF-TOKEN': sf_accessToken}
    req = urllib2.Request(orgs_url, headers=headers)
    resp = urllib2.urlopen(req)
    res = resp.read()
    all_res = json.loads(res)
    all_auth_tokens = []
    for i in all_res['rs']:
        all_auth_tokens.append((i['sf_organization'], i['sf_apiAccessToken']))

    if args.org is not None:
        for org_name, api_token in all_auth_tokens:
            if args.org == org_name:
                print(api_token)
                sys.exit(1)
        else:
            sys.stderr.write("Unable to find the org you set.\n")
            sys.exit(1)
    if args.error_on_multiple and len(all_auth_tokens) > 1:
        sys.stderr.write('User is part of more than one organization.\n')
        sys.exit(1)
    if args.print_token_only:
        for _, api_token in all_auth_tokens:
            print(api_token)
        sys.exit(1)
    for org_name, api_token in all_auth_tokens:
        if args.print_user_org or not org_name.startswith("per-user-org"):
            print("%40s%40s" % (org_name, api_token))
    if args.update is None:
        sys.exit(0)
    assert len(all_auth_tokens) != 0
    if len(all_auth_tokens) > 1:
        sys.stderr.write(
            "Multiple auth tokens associated with this account.  Add an --org tag for the auth token you want to update to.\n")
        examples = ["get_all_auth_tokens.py --org=\"%s\"" % s[0] for s in all_auth_tokens]
        sys.stderr.write("\n".join(examples)+"\n")
        sys.exit(1)

    replace_in_file(args.update, 'APIToken "(.*)"', 'APIToken "%s"' % all_auth_tokens[0][1])


def decode_string(str_to_decode):
    try:
        return str_to_decode.decode("UTF-8")
    except AttributeError:
        return str_to_decode


def replace_in_file(file_name, regex_to_change, new_subpart):
    p = re.compile(regex_to_change)
    f = open(file_name, 'rb')
    try:
        old_file_contents = decode_string(f.read())
    finally:
        f.close()

    (new_file_contents, num_replacements) = p.subn(new_subpart, old_file_contents)
    if num_replacements != 1:
        raise Exception("Invalid file format.  Please do auth token replacement manually")

    encoded_new_contents = new_file_contents.encode("UTF-8")
    f = open(file_name, 'wb')
    try:
        f.write(encoded_new_contents)
    finally:
        f.close()


if __name__ == '__main__':
    main()
