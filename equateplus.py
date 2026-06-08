"""
Showcase for EquatePlus scraping

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
    quantity = get_data(
        data,
        ("QUANTITY", "AVAIL_QTY", "LOCKED_QTY", "LOCKED_PERF_QTY"),
    )
    if quantity is None:
        return None
    return quantity["amount"]


class EquatePlus:
    def __init__(
        self,
        username: str,
        password: str,
        qr_code_path: Path,
    ) -> None:
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
        # True when SMS OTP flow completes login
        self.skip_equateaccess: bool = False

        self.session.hooks.update({
            "response": [
                self.set_csrf,
            ],
        })
        # Default headers
        self.session.headers["Accept"] = "*/*"

    def set_csrf(self, response: requests.Response, **_kwargs) -> None:
        prefix = b"csrfRegisterAjax(\"csrfpId\", \""
        if prefix in response.content:
            self.csrf = (
                response.content.split(prefix)[1]
                .split(b"\")")[0]
                .decode("utf-8")
            )
            self.session.headers["csrfpId"] = self.csrf

        # CSRF2 via JSON blob
        prefix = b",\"equateCsrfToken2\":\""
        if prefix in response.content:
            self.session.headers["EQUATE-CSRF2-TOKEN-PARTICIPANT2"] = (
                response.content.split(prefix)[1]
                .split(b"\",")[0]
                .decode("utf-8")
            )
        else:
            # CSRF2 via HTML hidden input
            marker = b"name=\"EQUATE-CSRF2-TOKEN-PARTICIPANT2\" value=\""
            if marker in response.content:
                token = (
                    response.content.split(marker)[1]
                    .split(b"\"")[0]
                    .decode("utf-8")
                )
                self.session.headers["EQUATE-CSRF2-TOKEN-PARTICIPANT2"] = token

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
        # Detect SMS OTP flow
        markers = (
            b'id="otpCodeId"',
            b'class="otpCodeSms"',
            b'Security Step Code',
        )
        if any(m in response.content for m in markers):
            # Prompt for OTP and verify
            for _ in range(3):
                code = click.prompt(
                    "Please enter the SMS code",
                    hide_input=True,
                )
                verify: requests.Response = self.session.post(
                    "https://www.equateplus.com/EquatePlusParticipant2/?login",
                    data={
                        "csrfpId": self.csrf,
                        # Field id is otpCodeId; name is typically otpCode
                        "otpCode": code,
                        "result": "verify",
                    },
                    headers={
                        "Content-Type": "application/x-www-form-urlencoded",
                    },
                )
                if b'id="otpCodeId"' in verify.content:
                    # Still on OTP page; try again
                    continue
                # Complete login and skip EquateAccess QR flow
                ok = self.complete_login()
                self.skip_equateaccess = ok
                return ok
            return False

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
            self.qr_code_path.write_bytes(
                b64decode(
                    data["dispatcherInformation"]["response"] + "=="
                )
            )
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
        # Try POST first
        response: requests.Response = self.session.post(
            (
                "https://www.equateplus.com/EquatePlusParticipant2/"
                "services/planSummary/get"
            ),
            params=self.ids(),
            json={"$type": "Object"},
            headers={
                "Referer": (
                    "https://www.equateplus.com/EquatePlusParticipant2/"
                ),
            },
        )

        def _parse_and_store(resp: requests.Response) -> bool:
            try:
                data = resp.json()
                self.plan_ids = [
                    plan["id"] for plan in data.get("entries", [])
                ]
                return (
                    not data.get("empty", False)
                    and len(self.plan_ids) > 0
                )
            except (
                ValueError,
                requests.exceptions.JSONDecodeError,
                AttributeError,
            ):
                return False

        if _parse_and_store(response):
            return True

        # Fallback to GET
        response = self.session.get(
            (
                "https://www.equateplus.com/EquatePlusParticipant2/"
                "services/planSummary/get"
            ),
            params=self.ids(),
            headers={
                "Referer": (
                    "https://www.equateplus.com/EquatePlusParticipant2/"
                ),
            },
        )
        return _parse_and_store(response)

    @debug
    def get_plan_details(self) -> bool:
        for plan_id in self.plan_ids:
            response: requests.Response = self.session.post(
                (
                    "https://www.equateplus.com/EquatePlusParticipant2/"
                    "services/planDetails/get"
                ),
                params=self.ids(),
                json={
                    "$type": "EntityIdentifier",
                    "id": plan_id,
                },
                headers={
                    "Referer": (
                        "https://www.equateplus.com/EquatePlusParticipant2/"
                    ),
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
                            self.securities[name] = (
                                self.securities.get(name, 0) + amount
                            )
            except (KeyError, IndexError):
                return False

        print(" ", end="", flush=True)
        return True

    @debug
    def get_documents(self) -> bool:
        response: requests.Response = self.session.post(
            (
                "https://www.equateplus.com/EquatePlusParticipant2/"
                "services/documents/library"
            ),
            params=self.ids(),
            json={
                "$type": "Object",
            },
            headers={
                "Referer": (
                    "https://www.equateplus.com/EquatePlusParticipant2/"
                ),
            },
        )
        try:
            for document in response.json()["documents"]:
                date: str = datetime.fromisoformat(document["date"]).strftime(
                    "%d.%m.%Y"
                )
                file_name: str = document["description"] + f" ({date}).pdf"
                file_path: Path = self.documents_dir / file_name.replace(
                    "/",
                    "-",
                )

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
            (
                "https://www.equateplus.com/EquatePlusParticipant2/"
                "services/statements/download"
            ),
            params={
                "documentId": document_id,
                "downloadType": "inline",
                "source": "LIBRARY",
            },
            headers={
                "Referer": (
                    "https://www.equateplus.com/EquatePlusParticipant2/"
                ),
            },
        )
        if response.content.startswith(b"{\"$type\":\"TechnicalError\""):
            return False

        try:
            file_path.parent.mkdir(parents=True, exist_ok=True)
            file_path.write_bytes(response.content)
        
        except OSError:
            return False

        return True

    @debug
    def logout(self) -> None:
        self.session.get(
            (
                "https://www.equateplus.com/EquatePlusParticipant2/"
                "services/participant/logout"
            ),
        )


# Path handling
# - Default paths are relative to the script directory (not CWD).
# - For relative paths, the script directory is also checked as a fallback.
SCRIPT_DIR: Path = Path(__file__).resolve().parent


@click.command()
@click.option(
    "--credentials-path",
    type=Path,
    default=SCRIPT_DIR / "credentials.txt",
    show_default=True,
)
@click.option(
    "--qr-code-path",
    type=Path,
    default=SCRIPT_DIR / "equateplus_qr.png",
    show_default=True,
)
@click.option(
    "--pickle-path",
    type=Path,
    default=SCRIPT_DIR / "equateplus.pckl",
    show_default=True,
)
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
def main(
    credentials_path: Path,
    qr_code_path: Path,
    pickle_path: Path,
    download_documents: bool,
    store: bool,
    restore: bool,
    no_logout: bool,
) -> None:
    # If a relative path is provided and does not exist in CWD,
    # also check relative to the script directory.
    if not credentials_path.exists():
        if not credentials_path.is_absolute():
            alt = (SCRIPT_DIR / credentials_path).resolve()
            if alt.exists():
                credentials_path = alt
        if not credentials_path.exists():
            raise FileNotFoundError(
                f"Credentials file not found: {credentials_path}"
            )

    # Same handling for QR and pickle paths so artifacts end up in the
    # script directory
    if not qr_code_path.is_absolute():
        qr_code_path = (SCRIPT_DIR / qr_code_path).resolve()
    if not pickle_path.is_absolute():
        pickle_path = (SCRIPT_DIR / pickle_path).resolve()

    credentials: list[str] = credentials_path.read_text().strip().split("\n")
    equateplus = EquatePlus(
        username=credentials[0],
        password=credentials[1],
        qr_code_path=qr_code_path,
    )
    login_successful: bool = False
    try:
        if restore:
            equateplus = loads(pickle_path.read_bytes())
            print("equateplus restored")
            login_successful = True

        else:
            login_successful = (
                equateplus.initialize()
                and equateplus.send_user()
                and equateplus.send_credentials()
                and (
                    equateplus.skip_equateaccess or (
                        equateplus.request_devices()
                        and equateplus.request_qr_code()
                        and equateplus.verify_qr_code()
                        and equateplus.complete_login()
                    )
                )
            )
        
        if store:
            if login_successful:
                pickle_path.write_bytes(dumps(equateplus))
                print("equateplus stored")
            else:
                print("equateplus not stored - login failed")

        if login_successful:
            equateplus.get_plan_summary()
            equateplus.get_plan_details()
            if download_documents:
                equateplus.get_documents()

    finally:
        if not store and not no_logout:
            equateplus.logout()
        else:
            print("equateplus not logged out")

    from pprint import pprint
    pprint(equateplus.securities)


if __name__ == "__main__":
    # click decorates `main` and supplies arguments at runtime.
    # pylint: disable=no-value-for-parameter
    main()  # type: ignore
