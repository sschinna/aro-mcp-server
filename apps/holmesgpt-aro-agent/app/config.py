from pydantic import BaseModel
from pydantic import Field
from pydantic import ValidationError
from pydantic import field_validator
from dotenv import load_dotenv
import os


load_dotenv()


class Settings(BaseModel):
    app_auth_token: str = Field(default="")

    azure_openai_endpoint: str = Field(default="")
    azure_openai_api_key: str = Field(default="")
    azure_openai_deployment_name: str = Field(default="gpt-4o-mini")
    azure_openai_api_version: str = Field(default="2024-10-21")

    aro_mcp_base_url: str = Field(default="http://127.0.0.1:8081")
    allow_update_tools: bool = Field(default=False)

    @field_validator("aro_mcp_base_url")
    @classmethod
    def trim_slash(cls, value: str) -> str:
        return value.rstrip("/")


    @classmethod
    def from_env(cls) -> "Settings":
        try:
            return cls(
                app_auth_token=os.getenv("APP_AUTH_TOKEN", ""),
                azure_openai_endpoint=os.getenv("AZURE_OPENAI_ENDPOINT", ""),
                azure_openai_api_key=os.getenv("AZURE_OPENAI_API_KEY", ""),
                azure_openai_deployment_name=os.getenv("AZURE_OPENAI_DEPLOYMENT_NAME", "gpt-4o-mini"),
                azure_openai_api_version=os.getenv("AZURE_OPENAI_API_VERSION", "2024-10-21"),
                aro_mcp_base_url=os.getenv("ARO_MCP_BASE_URL", "http://127.0.0.1:8081"),
                allow_update_tools=os.getenv("ALLOW_UPDATE_TOOLS", "false").lower() == "true",
            )
        except ValidationError as exc:
            raise RuntimeError(f"Invalid configuration: {exc}") from exc


settings = Settings.from_env()
