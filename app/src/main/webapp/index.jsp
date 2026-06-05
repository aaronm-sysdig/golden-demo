<%@ page contentType="text/html;charset=UTF-8" %>
<!DOCTYPE html>
<html>
<head>
  <title>Acme Financial Services - Sign In</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      background: #f0f2f5;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
    }
    .topbar {
      background: #1a1a2e;
      padding: 0 40px;
      height: 56px;
      display: flex;
      align-items: center;
    }
    .logo { display: flex; align-items: center; gap: 12px; color: #fff; font-size: 17px; font-weight: 700; }
    .logo-icon {
      width: 30px; height: 30px; background: #e63946; border-radius: 6px;
      display: flex; align-items: center; justify-content: center;
      font-size: 15px; font-weight: 900; color: #fff;
    }
    .main {
      flex: 1;
      display: flex;
      align-items: center;
      justify-content: center;
      padding: 40px;
    }
    .login-box {
      background: #fff;
      border-radius: 12px;
      border: 1px solid #e2e8f0;
      padding: 40px;
      width: 100%;
      max-width: 400px;
      box-shadow: 0 4px 24px rgba(0,0,0,0.06);
    }
    .login-box h1 { font-size: 22px; font-weight: 700; color: #1a1a2e; }
    .login-box p { font-size: 13px; color: #64748b; margin-top: 6px; margin-bottom: 28px; }
    label { display: block; font-size: 13px; font-weight: 600; color: #374151; margin-bottom: 6px; }
    input[type=text], input[type=password] {
      width: 100%; padding: 10px 14px; border: 1px solid #d1d5db;
      border-radius: 7px; font-size: 14px; color: #1a1a2e;
      background: #f9fafb; outline: none; margin-bottom: 16px;
    }
    input:focus { border-color: #2563eb; background: #fff; }
    .btn {
      width: 100%; padding: 11px; background: #1a1a2e; color: #fff;
      border: none; border-radius: 7px; font-size: 14px; font-weight: 600;
      cursor: pointer; margin-top: 4px;
    }
    .btn:hover { background: #2d2d4e; }
    .hint { font-size: 11px; color: #94a3b8; text-align: center; margin-top: 20px; }
    .footer { text-align: center; padding: 20px; font-size: 12px; color: #94a3b8; }
  </style>
</head>
<body>

<div class="topbar">
  <div class="logo">
    <div class="logo-icon">A</div>
    Acme Financial Services
  </div>
</div>

<div class="main">
  <div class="login-box">
    <h1>Customer Portal</h1>
    <p>Sign in to access your customer management dashboard.</p>

    <form action="customers.action" method="post">
      <label for="username">Username</label>
      <input type="text" id="username" name="username" value="admin" placeholder="Enter username">

      <label for="password">Password</label>
      <input type="password" id="password" name="password" placeholder="Enter password">

      <button type="submit" class="btn">Sign In</button>
    </form>

    <div class="hint">Internal use only &mdash; unauthorised access is prohibited</div>
  </div>
</div>

<div class="footer">
  &copy; 2024 Acme Financial Services &mdash; Confidential
</div>

</body>
</html>
