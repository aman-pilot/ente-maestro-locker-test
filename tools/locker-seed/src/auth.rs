use std::time::Duration;

use anyhow::{Context, Result};
use base64::{Engine, engine::general_purpose::URL_SAFE};
use ente_accounts::{
    AccountsClient, AccountsClientConfig, AuthFlow, AuthFlowUi, AuthenticatedAccount,
    CreateAccountParams, Error, LoginParams, OtpPurpose, SecondFactorMethod, TotpPurpose,
};
use zeroize::Zeroizing;

pub const CLIENT_PACKAGE: &str = "io.ente.locker";
const HARDCODED_OTT: &str = "123456";

struct LocalMuseumUi;

impl AuthFlowUi for LocalMuseumUi {
    fn read_email_otp(
        &mut self,
        _email: &str,
        _purpose: OtpPurpose,
        _resent: bool,
    ) -> ente_accounts::Result<String> {
        Ok(HARDCODED_OTT.to_owned())
    }

    fn read_totp_code(&mut self, _purpose: TotpPurpose) -> ente_accounts::Result<String> {
        Err(Error::InvalidInput(
            "TOTP is not supported for generated Locker test accounts".to_owned(),
        ))
    }

    fn report_retryable_error(&mut self, message: &str) -> ente_accounts::Result<()> {
        Err(Error::Generic(message.to_owned()))
    }

    fn choose_second_factor(
        &mut self,
        _methods: &[SecondFactorMethod],
    ) -> ente_accounts::Result<SecondFactorMethod> {
        Err(Error::InvalidInput(
            "second factor is not supported for generated Locker test accounts".to_owned(),
        ))
    }

    fn present_passkey_verification(&mut self, _url: &str) -> ente_accounts::Result<()> {
        Err(Error::InvalidInput(
            "passkeys are not supported for generated Locker test accounts".to_owned(),
        ))
    }

    fn wait_for_passkey_verification(&mut self) -> ente_accounts::Result<()> {
        Err(Error::InvalidInput(
            "passkeys are not supported for generated Locker test accounts".to_owned(),
        ))
    }

    fn present_totp_secret(
        &mut self,
        _secret_code: &str,
        _qr_code: &str,
    ) -> ente_accounts::Result<()> {
        Err(Error::InvalidInput(
            "TOTP setup is not supported for generated Locker test accounts".to_owned(),
        ))
    }
}

pub async fn create_account(
    endpoint: &str,
    email: &str,
    password: &str,
) -> Result<AuthenticatedAccount> {
    let client = accounts_client(endpoint)?;
    let mut ui = LocalMuseumUi;
    let mut flow = AuthFlow::new(&client, &mut ui);

    tokio::time::timeout(
        Duration::from_secs(180),
        flow.create_account(CreateAccountParams {
            email: email.to_owned(),
            password: Zeroizing::new(password.to_owned()),
            source: Some("lockerMaestroSeed".to_owned()),
        }),
    )
    .await
    .context("local Museum account creation timed out")?
    .context("local Museum account creation failed")
}

pub async fn login(endpoint: &str, email: &str, password: &str) -> Result<AuthenticatedAccount> {
    let client = accounts_client(endpoint)?;
    let mut ui = LocalMuseumUi;
    let mut flow = AuthFlow::new(&client, &mut ui);

    tokio::time::timeout(
        Duration::from_secs(90),
        flow.login(LoginParams {
            email: email.to_owned(),
            password: Zeroizing::new(password.to_owned()),
        }),
    )
    .await
    .context("local Museum login timed out")?
    .context("local Museum login failed")
}

pub fn encoded_token(account: &AuthenticatedAccount) -> String {
    URL_SAFE.encode(&account.secrets.token)
}

fn accounts_client(endpoint: &str) -> Result<AccountsClient> {
    AccountsClient::new(
        AccountsClientConfig::new(CLIENT_PACKAGE)
            .with_origin(endpoint.to_owned())
            .with_user_agent("locker-maestro-seed/0.1"),
    )
    .context("failed to construct Ente accounts client")
}
