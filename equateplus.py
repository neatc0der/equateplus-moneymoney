"""
Showcase for EquatePlus scrapping

Please provide:
- credentials.txt: username and password separated by newline

Please act during verify_qr_code:
- equateplus_qr.png: Scan QR code with EquateAccess app
"""
from base64 import b64decode
from datetime import datetime
from pathlib import Path
from pickle import dumps, loads
from random import randint
from time import sleep

import click
import requests


def debug(func):
    def wrapper(*args, **kwargs):
        print(func.__name__, end=" ", flush=True)
        result = func(*args, **kwargs)
        print("->", result)
        sleep(0.5)
        return result
    return wrapper


def random_digits(n):
    range_start = 10**(n-1)
    range_end = (10**n)-1
    return randint(range_start, range_end)


def get_data(data: dict, keys: tuple[str, ...]) -> str:
    for key in keys:
        if key in data and data[key] is not None:
            return data[key]


def get_name(data: dict) -> str:
    return get_data(data, ("VEHICLE", "VEHICLE_DESCRIPTION"))


def get_amount(data: dict) -> float:
    quantity = get_data(data, ("QUANTITY", "AVAIL_QTY", "LOCKED_QTY", "LOCKED_PERF_QTY"))
    if quantity is None:
        return None
    return quantity["amount"]


class EquatePlus:
    def __init__(self, username: str, password: str, qr_code_path: Path) -> None:
        self.username: str = username
        self.password: str = password
        self.qr_code_path: Path = qr_code_path
        self.documents_dir: Path = Path("documents")

        self.session: requests.Session = requests.Session()
        self.cookies: dict[str, str] = {}
        self.csrf: str | None = None
        self.csrf2: str | None = None
        self.device_id: str | None = None
        self.session_id: str | None = None
        self.cid: str = "eqp." + str(random_digits(7))
        self.plan_ids: list[str] = []
        self.securities: dict[str, float] = {}

        self.session.hooks.update({
            "response": [
                self.set_csrf,
            ],
        })

    def set_csrf(self, response: requests.Response, **kwargs) -> None:
        prefix = b"csrfRegisterAjax(\"csrfpId\", \""
        if prefix in response.content:
            self.csrf = response.content.split(prefix)[1].split(b"\")")[0].decode("utf-8")
            self.session.headers["csrfpId"] = self.csrf

        prefix = b",\"equateCsrfToken2\":\""
        if prefix in response.content:
            self.session.headers["EQUATE-CSRF2-TOKEN-PARTICIPANT2"] = response.content.split(prefix)[1].split(b"\",")[0].decode("utf-8")

    def ids(self) -> dict[str, str]:
        return {
            "_cId": self.cid,
            "_rId": str(random_digits(8)),
        }

    @debug
    def initialize(self) -> bool:
        response: requests.Response = self.session.get(
            "https://www.equateplus.com/EquatePlusParticipant2/?login",
        )
        
        return b"isiwebuserid" in response.content

    @debug
    def send_user(self) -> bool:
        response: requests.Response = self.session.post(
            "https://www.equateplus.com/EquatePlusParticipant2/?login",
            params={
                "csrfpId": self.csrf,
            },
            data={
                "csrfpId": self.csrf,
                "isiwebuserid": self.username,
                "result": "Continue Login",
            },
            headers={
                "Content-Type": "application/x-www-form-urlencoded",
            },)
        return b"isiwebpasswd" in response.content

    @debug
    def send_credentials(self) -> bool:
        response: requests.Response = self.session.post(
            "https://www.equateplus.com/EquatePlusParticipant2/?login",
            data={
                "csrfpId": self.csrf,
                "isiwebuserid": self.username,
                "isiwebpasswd": self.password,
                "result": "Continue",
            },
            headers={
                "Content-Type": "application/x-www-form-urlencoded",
            },
        )
        return b"EquateAccess app" in response.content

    @debug
    def request_devices(self) -> bool:
        response: requests.Response = self.session.post(
            "https://www.equateplus.com/EquatePlusParticipant2/?login",
            data={
                "isiwebuserid": self.username,
                "isiwebpasswd": "null",
                "result": "null",
            },
            headers={
                "Content-Type": "application/x-www-form-urlencoded",
            },
        )

        try:
            self.device_id = response.json()["dispatchTargets"][0]["id"]
            return True
        except (KeyError, IndexError):
            return False

    @debug
    def request_qr_code(self) -> bool:
        response: requests.Response = self.session.get(
            "https://www.equateplus.com/EquatePlusParticipant2/?login",
            params={
                "o.dispatchTargetId.v": self.device_id,
                **self.ids(),
            },
            headers={
                "Content-Type": "application/x-www-form-urlencoded",
            },
        )

        try:
            data = response.json()
            self.qr_code_path.write_bytes(b64decode(data["dispatcherInformation"]["response"] + "=="))
            self.session_id = data["sessionId"]

            return True
        except (KeyError, IndexError):
            return False

    @debug
    def verify_qr_code(self) -> bool:
        while True:
            sleep(1.0)
            response: requests.Response = self.session.get(
                "https://www.equateplus.com/EquatePlusParticipant2/?login",
                params={
                    "o.fidoUafSessionId.v": self.session_id,
                    **self.ids(),
                },
                headers={
                    "Content-Type": "application/x-www-form-urlencoded",
                },
            )
            
            print(".", end="", flush=True)

            try:
                result = response.json()["status"]
            except (KeyError, IndexError):
                print(response.content)
                break
            if result in ("succeeded", "failed_retry_please", "failed"):
                break

        print(" ", end="", flush=True)
        return result == "succeeded"

    @debug
    def complete_login(self) -> bool:
        response: requests.Response = self.session.post(
            "https://www.equateplus.com/EquatePlusParticipant2/?login",
            data={
                "result": "Continue",
            },
            headers={
                "Content-Type": "application/x-www-form-urlencoded",
            },
        )
        return b"TopLoaderSkeleton" in response.content

    @debug
    def get_plan_summary(self) -> bool:
        response: requests.Response = self.session.get(
            "https://www.equateplus.com/EquatePlusParticipant2/services/planSummary/get",
            params=self.ids(),
        )

        try:
            data = response.json()
            self.plan_ids = [plan["id"] for plan in data["entries"]]
            return not data["empty"]
        except (KeyError, IndexError):
            return False

    @debug
    def get_plan_details(self) -> bool:
        for plan_id in self.plan_ids:
            response: requests.Response = self.session.post(
                "https://www.equateplus.com/EquatePlusParticipant2/services/planDetails/get",
                params=self.ids(),
                json={
                    "$type": "EntityIdentifier",
                    "id": plan_id,
                },
            )
            print(".", end="", flush=True)
            try:
                for plan_groups in response.json()["entries"]:
                    for plan_details in plan_groups["entries"]:
                        for value in plan_details["entries"]:
                            name = get_name(value)
                            amount = get_amount(value)
                            if amount is None:
                                continue
                            self.securities[name] = self.securities.get(name, 0) + amount
            except (KeyError, IndexError):
                return False

        print(" ", end="", flush=True)
        return True

    @debug
    def get_documents(self) -> bool:
        response: requests.Response = self.session.post(
            "https://www.equateplus.com/EquatePlusParticipant2/services/documents/library",
            params=self.ids(),
            json={
                "$type": "Object",
            },
        )
        try:
            for document in response.json()["documents"]:
                date: str = datetime.fromisoformat(document["date"]).strftime("%d.%m.%Y")
                file_name: str = document["description"] + f" ({date}).pdf"
                file_path: Path = self.documents_dir / file_name.replace("/", "-")

                if self.download_document(document["id"], file_path):
                    print(".", end="", flush=True)
                else:
                    print("x", end="", flush=True)

        except (KeyError, IndexError):
            return False
        
        print(" ", end="", flush=True)
        return True

    def download_document(self, document_id: str, file_path: Path) -> bool:
        response: requests.Response = self.session.get(
            "https://www.equateplus.com/EquatePlusParticipant2/services/statements/download",
            params={
                "documentId": document_id,
                "downloadType": "inline",
                "source": "LIBRARY",
            },
        )
        if response.content.startswith(b"{\"$type\":\"TechnicalError\""):
            return False

        try:
            file_path.parent.mkdir(parents=True, exist_ok=True)
            file_path.write_bytes(response.content)
        
        except:
            return False

        return True

    @debug
    def logout(self) -> None:
        self.session.get(
            "https://www.equateplus.com/EquatePlusParticipant2/services/participant/logout",
        )


@click.command()
@click.option("--credentials-path", type=Path, default=Path("credentials.txt"), show_default=True)
@click.option("--qr-code-path", type=Path, default=Path("equateplus_qr.png"), show_default=True)
@click.option("--pickle-path", type=Path, default=Path("equateplus.pckl"), show_default=True)
@click.option("--download-documents", is_flag=True, help="download documents")
@click.option(
    "--store",
    is_flag=True,
    help="serialize EquatePlus object to file (and don't logout)",
)
@click.option(
    "--restore",
    is_flag=True,
    help="deserialize EquatePlus object from file (and don't login)",
)
@click.option("--no-logout", is_flag=True, help="don't logout")
def main(credentials_path: Path, qr_code_path: Path, pickle_path: Path, download_documents: bool, store: bool, restore: bool, no_logout: bool) -> None:
    credentials: list[str] = credentials_path.read_text().strip().split("\n")
    equateplus = EquatePlus(username=credentials[0], password=credentials[1], qr_code_path=qr_code_path)
    login_successful: bool = False
    try:
        if restore:
            equateplus = loads(pickle_path.read_bytes())
            print("equateplus restored")
            login_successful = True

        else:
            login_successful = equateplus.initialize() and \
            equateplus.send_user() and \
            equateplus.send_credentials() and \
            equateplus.request_devices() and \
            equateplus.request_qr_code() and \
            equateplus.verify_qr_code() and \
            equateplus.complete_login()
        
        if store:
            if login_successful:
                pickle_path.write_bytes(dumps(equateplus))
                print("equateplus stored")
            else:
                print("equateplus not stored - login failed")

        login_successful and \
        equateplus.get_plan_summary() and \
        equateplus.get_plan_details() and \
        download_documents and \
        equateplus.get_documents()

    finally:
        if not store and not no_logout:
            equateplus.logout()
        else:
            print("equateplus not logged out")

    from pprint import pprint
    pprint(equateplus.securities)


if __name__ == "__main__":
    main()
