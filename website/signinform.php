<!DOCTYPE html>
<html>
	<head>
		<title>signinform</title>
		<meta charset="utf-8">
	</head>
	<div align="center">
		<h2>LOG IN</h2>
		<br /><br />
		<form method="post" action="signin.php">
			<label for="email">Email :</label>
			<input type="text" name="email" placeholder="Enter your email" autocomplete="off"/>
			<br/>
			<label for="passw">Password :</label>
			<input type="password" name="passw" placeholder="Enter your password" autocomplete="off"/>
			<br/><br/>
			<input type="submit" name="signinform" value="SIGN IN">
		</form>
		<?php
			if (isset($_GET['error']))
			{
				echo '<br/>' . $_GET['error'];
				if ($_GET['error'] == 'You are not registered.') {
					?>
					<div align="center">
						<a href="signupform.php">SIGN UP</a><br>
					</div>
					<?php
				$_GET['error'] = NULL;
			}
		?>
	</div>
</html>
